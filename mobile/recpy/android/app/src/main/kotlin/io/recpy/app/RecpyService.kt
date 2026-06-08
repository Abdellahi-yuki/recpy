package io.recpy.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.provider.OpenableColumns
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.*
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * A bound + started foreground Service that owns all socket I/O.
 * Runs independently of the Flutter activity — survives backgrounding,
 * screen-off, and file picker transitions.
 *
 * Flutter talks to it via MethodChannel "io.recpy.app/service".
 * The service calls back on "io.recpy.app/service_events".
 */
class RecpyService : Service() {

    companion object {
        const val METHOD_CHANNEL  = "io.recpy.app/service"
        const val EVENT_CHANNEL   = "io.recpy.app/service_events"
        const val NOTIF_CHANNEL   = "recpy_service"
        const val NOTIF_ID        = 1001

        // Set by MainActivity so the service can call back into Flutter
        var flutterEngine: FlutterEngine? = null
    }

    // ── Binder so MainActivity can get a reference ────────────────────────
    inner class LocalBinder : Binder() {
        fun getService(): RecpyService = this@RecpyService
    }
    private val binder = LocalBinder()

    // ── Coroutine scope — cancelled on destroy ────────────────────────────
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // ── Wake lock — keeps CPU alive ───────────────────────────────────────
    private var wakeLock: PowerManager.WakeLock? = null

    // ── Server socket for receive mode ────────────────────────────────────
    private var serverSocket: ServerSocket? = null
    private var isListening = false

    // ── Cancel flags ──────────────────────────────────────────────────────
    private var sendCancelFlag = false

    // ── Method channel (set when Flutter engine is available) ─────────────
    private var methodChannel: MethodChannel? = null

    // ─────────────────────────────────────────────────────────────────────
    // Service lifecycle
    // ─────────────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification("recpy", "Ready"))
        acquireWakeLock()
        setupMethodChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent): IBinder = binder

    override fun onDestroy() {
        stopReceiver()
        scope.cancel()
        wakeLock?.release()
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────────────
    // Flutter method channel
    // ─────────────────────────────────────────────────────────────────────

    private fun setupMethodChannel() {
        val engine = flutterEngine ?: return
        methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startReceiver" -> {
                    val port = call.argument<Int>("port") ?: 12345
                    startReceiver(port, result)
                }
                "stopReceiver" -> {
                    stopReceiver()
                    result.success(null)
                }
                "sendText" -> {
                    val ip   = call.argument<String>("ip") ?: return@setMethodCallHandler result.error("NO_IP", null, null)
                    val port = call.argument<Int>("port") ?: return@setMethodCallHandler result.error("NO_PORT", null, null)
                    val text = call.argument<String>("text") ?: return@setMethodCallHandler result.error("NO_TEXT", null, null)
                    sendText(ip, port, text, result)
                }
                "sendFile" -> {
                    val ip      = call.argument<String>("ip") ?: return@setMethodCallHandler result.error("NO_IP", null, null)
                    val port    = call.argument<Int>("port") ?: return@setMethodCallHandler result.error("NO_PORT", null, null)
                    val uri     = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("NO_URI", null, null)
                    val name    = call.argument<String>("name") ?: "file"
                    val size    = (call.argument<Any>("size") as? Number)?.toLong() ?: 0L
                    sendFile(ip, port, uri, name, size, result)
                }
                "cancelSend" -> {
                    sendCancelFlag = true
                    result.success(null)
                }
                "isListening" -> result.success(isListening)
                else -> result.notImplemented()
            }
        }
    }

    // Re-attach channel when Flutter engine reconnects after activity recreation
    fun reattach(engine: FlutterEngine) {
        flutterEngine = engine
        setupMethodChannel()
    }

    // ─────────────────────────────────────────────────────────────────────
    // Callbacks into Flutter
    // ─────────────────────────────────────────────────────────────────────

    private fun emit(event: String, data: Any?) {
        val engine = flutterEngine ?: return
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        mainThread { ch.invokeMethod(event, data) }
    }

    private fun mainThread(block: () -> Unit) {
        android.os.Handler(mainLooper).post(block)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Receive server
    // ─────────────────────────────────────────────────────────────────────

    private fun startReceiver(port: Int, result: MethodChannel.Result) {
        if (isListening) { result.success(null); return }
        scope.launch {
            try {
                serverSocket = ServerSocket(port)
                isListening  = true
                updateNotification("recpy is listening", "Waiting on port $port…")
                mainThread { result.success(null) }
                emit("onStatusChanged", "Listening on port $port...")

                while (isListening) {
                    try {
                        val client = serverSocket!!.accept()
                        launch { handleClient(client) }
                    } catch (e: SocketException) {
                        break // socket closed intentionally
                    }
                }
            } catch (e: Exception) {
                isListening = false
                mainThread { result.error("BIND_ERROR", e.message, null) }
                emit("onError", "Failed to bind: ${e.message}")
            }
        }
    }

    fun stopReceiver() {
        isListening = false
        try { serverSocket?.close() } catch (_: Exception) {}
        serverSocket = null
        updateNotification("recpy", "Ready")
        emit("onStatusChanged", "Stopped")
    }

    private suspend fun handleClient(socket: Socket) {
        val clientIp = socket.inetAddress.hostAddress ?: "unknown"
        val buf      = ByteArray(256 * 1024)
        val accum    = ByteArrayOutputStream()

        // State machine identical to the Dart one
        var state           = 0
        var expectedLen     = 6
        var commandType     = 0
        var textLen         = 0
        var fileCount       = 0
        var fileIndex       = 0
        var nameLen         = 0
        var currentName     = ""
        var fileContentLen  = 0L
        var tempFile: File? = null
        var fileOut: OutputStream? = null
        var fileWritten     = 0L

        val downloadDir = getDownloadDirectory()

        fun cleanup() {
            try { fileOut?.close() } catch (_: Exception) {}
            try { socket.close()  } catch (_: Exception) {}
        }

        try {
            val ins = socket.getInputStream()
            var read: Int
            while (ins.read(buf).also { read = it } != -1) {
                accum.write(buf, 0, read)

                // Process all complete frames in the accumulator
                var progress = true
                while (progress) {
                    val bytes = accum.toByteArray()

                    if (state == 7) {
                        // Streaming file body
                        if (bytes.isEmpty()) { progress = false; break }
                        accum.reset()

                        val remaining  = fileContentLen - fileWritten
                        val use        = minOf(bytes.size.toLong(), remaining).toInt()
                        fileOut?.write(bytes, 0, use)
                        fileWritten += use

                        val pct = if (fileContentLen > 0) fileWritten.toDouble() / fileContentLen else 1.0
                        emit("onTransferProgress", mapOf(
                            "clientIp" to clientIp,
                            "info"     to "Receiving $currentName (${fileIndex + 1}/$fileCount)",
                            "progress" to pct,
                        ))

                        if (use < bytes.size) accum.write(bytes, use, bytes.size - use)

                        if (fileWritten >= fileContentLen) {
                            fileOut?.flush(); fileOut?.close(); fileOut = null

                            // Move temp → download dir (copy+delete for cross-partition safety)
                            var dest = File(downloadDir, currentName)
                            var ctr  = 1
                            while (dest.exists()) {
                                val ext  = currentName.substringAfterLast('.', "")
                                val base = if (ext.isEmpty()) currentName else currentName.dropLast(ext.length + 1)
                                dest = File(downloadDir, if (ext.isEmpty()) "${base}_$ctr" else "${base}_$ctr.$ext")
                                ctr++
                            }
                            tempFile?.copyTo(dest, overwrite = false)
                            tempFile?.delete()
                            tempFile = null

                            emit("onFileReceived", mapOf(
                                "clientIp"  to clientIp,
                                "filename"  to currentName,
                                "savedPath" to dest.absolutePath,
                            ))

                            fileIndex++
                            if (fileIndex >= fileCount) { cleanup(); return }
                            state = 4; expectedLen = 4
                        }
                    } else {
                        if (bytes.size < expectedLen) { progress = false; break }
                        val frame     = bytes.copyOf(expectedLen)
                        val remainder = bytes.copyOfRange(expectedLen, bytes.size)
                        accum.reset()
                        accum.write(remainder)

                        val bb = ByteBuffer.wrap(frame).order(ByteOrder.BIG_ENDIAN)

                        when (state) {
                            0 -> {
                                val magic = String(frame.copyOf(5), Charsets.UTF_8)
                                if (magic != "RECPY") { emit("onError", "Bad magic"); cleanup(); return }
                                commandType = frame[5].toInt() and 0xFF
                                when (commandType) {
                                    1 -> { state = 1; expectedLen = 4 }
                                    2 -> { state = 3; expectedLen = 4 }
                                    else -> { emit("onError", "Unknown type $commandType"); cleanup(); return }
                                }
                            }
                            1 -> { textLen = bb.int; state = 2; expectedLen = textLen }
                            2 -> {
                                val text = String(frame, Charsets.UTF_8)
                                emit("onTextReceived", mapOf("clientIp" to clientIp, "text" to text))
                                cleanup(); return
                            }
                            3 -> { fileCount = bb.int; fileIndex = 0; state = 4; expectedLen = 4 }
                            4 -> { nameLen = bb.int; state = 5; expectedLen = nameLen }
                            5 -> {
                                currentName = String(frame, Charsets.UTF_8)
                                state = 6; expectedLen = 8
                            }
                            6 -> {
                                fileContentLen = bb.long; fileWritten = 0
                                val tmp = File(cacheDir, "recpy_${System.currentTimeMillis()}")
                                tempFile = tmp; fileOut = tmp.outputStream()
                                emit("onTransferProgress", mapOf(
                                    "clientIp" to clientIp,
                                    "info"     to "Receiving $currentName (${fileIndex + 1}/$fileCount)",
                                    "progress" to 0.0,
                                ))
                                state = 7; expectedLen = 0
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            emit("onError", "Client error: ${e.message}")
        } finally {
            cleanup()
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Send text
    // ─────────────────────────────────────────────────────────────────────

    private fun sendText(ip: String, port: Int, text: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                Socket(ip, port).use { socket ->
                    val out     = socket.getOutputStream()
                    val textB   = text.toByteArray(Charsets.UTF_8)
                    val lenBuf  = ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(textB.size).array()
                    out.write("RECPY".toByteArray())
                    out.write(byteArrayOf(1))
                    out.write(lenBuf)
                    out.write(textB)
                    out.flush()
                }
                mainThread { result.success(null) }
            } catch (e: Exception) {
                mainThread { result.error("SEND_ERROR", e.message, null) }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Send file (streams from ContentResolver — no temp copy)
    // ─────────────────────────────────────────────────────────────────────

    private fun sendFile(ip: String, port: Int, uriString: String, name: String, size: Long, result: MethodChannel.Result) {
        sendCancelFlag = false
        updateNotification("recpy is sending", name)
        scope.launch {
            try {
                val uri   = Uri.parse(uriString)
                val ins   = contentResolver.openInputStream(uri)
                    ?: throw IOException("Cannot open: $uriString")

                Socket(ip, port).use { socket ->
                    val out = socket.getOutputStream()

                    // Protocol: RECPY + type=2 + count=1 + nameLen + name + fileLen + body
                    val nameB    = name.toByteArray(Charsets.UTF_8)
                    val hdr      = ByteBuffer.allocate(5 + 1 + 4 + 4 + nameB.size + 8)
                        .order(ByteOrder.BIG_ENDIAN)
                    hdr.put("RECPY".toByteArray())
                    hdr.put(2)                       // type
                    hdr.putInt(1)                    // count
                    hdr.putInt(nameB.size)           // name length
                    hdr.put(nameB)
                    hdr.putLong(size)
                    out.write(hdr.array())
                    out.flush()

                    val buf  = ByteArray(256 * 1024)
                    var sent = 0L
                    var read: Int
                    ins.use { stream ->
                        while (stream.read(buf).also { read = it } != -1) {
                            if (sendCancelFlag) break
                            out.write(buf, 0, read)
                            out.flush()
                            sent += read
                            val pct = if (size > 0) sent.toDouble() / size else 1.0
                            emit("onSendProgress", mapOf("name" to name, "progress" to pct))
                        }
                    }
                }

                val success = !sendCancelFlag
                mainThread { result.success(success) }
            } catch (e: Exception) {
                mainThread { result.error("SEND_ERROR", e.message, null) }
            } finally {
                updateNotification("recpy", "Ready")
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────

    private fun getDownloadDirectory(): File {
        // Try the saved path from SharedPreferences
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val saved = prefs.getString("flutter.download_path", null)
        if (!saved.isNullOrEmpty() && !saved.startsWith("content://")) {
            val dir = File(saved)
            if (dir.exists() || dir.mkdirs()) return dir
        }
        return File(android.os.Environment.getExternalStoragePublicDirectory(
            android.os.Environment.DIRECTORY_DOWNLOADS
        ).absolutePath)
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "recpy::TransferLock"
        ).apply { acquire(10 * 60 * 60 * 1000L) } // max 10h
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                NOTIF_CHANNEL, "recpy Transfers",
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Keeps transfers running in the background" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    private fun buildNotification(title: String, text: String): Notification {
        val pi = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, NOTIF_CHANNEL)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(title: String, text: String) {
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIF_ID, buildNotification(title, text))
    }
}
