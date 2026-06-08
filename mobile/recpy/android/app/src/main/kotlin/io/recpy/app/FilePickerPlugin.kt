package io.recpy.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class FilePickerPlugin(
    private val activity: FlutterActivity,
    private val messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val METHOD_CHANNEL = "io.recpy.app/file_picker"
        private const val STREAM_BASE = "io.recpy.app/file_stream"
        private const val REQUEST_CODE = 7842

        fun register(activity: FlutterActivity, messenger: BinaryMessenger) {
            val plugin = FilePickerPlugin(activity, messenger)
            MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(plugin)
        }
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var pendingPickResult: MethodChannel.Result? = null

    init {
        ActivityResultRegistry.register(activity) { requestCode, resultCode, data ->
            if (requestCode == REQUEST_CODE) {
                handlePickerResult(resultCode, data)
                true
            } else false
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFiles" -> pickFiles(result)
            "registerStream" -> {
                // Dart calls this to get a stream channel registered for a URI.
                // We register a fresh EventChannel handler for the unique channel name.
                val uri = call.argument<String>("uri") ?: return result.error("NO_URI", null, null)
                val chunkSize = call.argument<Int>("chunkSize") ?: (256 * 1024)
                registerFileStream(uri, chunkSize)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun registerFileStream(uriString: String, chunkSize: Int) {
        val channelName = "$STREAM_BASE/${Uri.encode(uriString)}"
        EventChannel(messenger, channelName).setStreamHandler(
            FileStreamHandler(activity, uriString, chunkSize, scope)
        )
    }

    private fun pickFiles(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("ALREADY_ACTIVE", "Picker already open", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_CODE)
    }

    private fun handlePickerResult(resultCode: Int, data: Intent?) {
        val pending = pendingPickResult ?: return
        pendingPickResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            pending.success(null)
            return
        }

        scope.launch {
            try {
                val uris = mutableListOf<Uri>()
                val clipData = data.clipData
                if (clipData != null) {
                    for (i in 0 until clipData.itemCount) uris.add(clipData.getItemAt(i).uri)
                } else {
                    data.data?.let { uris.add(it) }
                }

                uris.forEach { uri ->
                    try {
                        activity.contentResolver.takePersistableUriPermission(
                            uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                        )
                    } catch (_: Exception) {}
                }

                // For each URI, pre-register its stream channel so it's ready
                // before Dart tries to listen on it.
                uris.forEach { uri ->
                    registerFileStream(uri.toString(), 256 * 1024)
                }

                val files = uris.map { queryFileInfo(it) }
                withContext(Dispatchers.Main) { pending.success(files) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { pending.error("PICKER_ERROR", e.message, null) }
            }
        }
    }

    private fun queryFileInfo(uri: Uri): Map<String, Any> {
        var name = uri.lastPathSegment ?: "file"
        var size = 0L
        activity.contentResolver.query(
            uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null, null, null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val ni = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val si = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (ni >= 0) name = cursor.getString(ni)
                if (si >= 0 && !cursor.isNull(si)) size = cursor.getLong(si)
            }
        }
        return mapOf("uri" to uri.toString(), "name" to name, "size" to size)
    }
}

// Separate class per stream so each file gets its own independent handler.
private class FileStreamHandler(
    private val activity: FlutterActivity,
    private val uriString: String,
    private val chunkSize: Int,
    private val scope: CoroutineScope,
) : EventChannel.StreamHandler {

    private var job: Job? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        job = scope.launch {
            try {
                val uri = Uri.parse(uriString)
                val inputStream = activity.contentResolver.openInputStream(uri)
                    ?: throw Exception("Cannot open stream for: $uriString")

                val buf = ByteArray(chunkSize)
                var bytesRead: Int
                inputStream.use { ins ->
                    while (ins.read(buf).also { bytesRead = it } != -1) {
                        // Copy only the bytes actually read — avoids sending
                        // zero-padded tail of the buffer on the last chunk.
                        val chunk = buf.copyOf(bytesRead)
                        withContext(Dispatchers.Main) { events.success(chunk) }
                    }
                }
                withContext(Dispatchers.Main) { events.endOfStream() }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    events.error("STREAM_ERROR", e.message, null)
                }
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        job?.cancel()
        job = null
    }
}

typealias ActivityResultCallback = (requestCode: Int, resultCode: Int, data: Intent?) -> Boolean

object ActivityResultRegistry {
    private val callbacks = mutableMapOf<FlutterActivity, MutableList<ActivityResultCallback>>()

    fun register(activity: FlutterActivity, callback: ActivityResultCallback) {
        callbacks.getOrPut(activity) { mutableListOf() }.add(callback)
    }

    fun dispatch(activity: FlutterActivity, requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        return callbacks[activity]?.any { it(requestCode, resultCode, data) } ?: false
    }

    fun unregister(activity: FlutterActivity) {
        callbacks.remove(activity)
    }
}
