package io.recpy.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var recpyService: RecpyService? = null
    private var serviceBound = false

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            recpyService = (binder as RecpyService.LocalBinder).getService()
            serviceBound = true
            // Give the service the current Flutter engine so it can call back
            flutterEngine?.let { recpyService?.reattach(it) }
        }
        override fun onServiceDisconnected(name: ComponentName) {
            serviceBound = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Store engine reference for the service
        RecpyService.flutterEngine = flutterEngine

        // Register file picker plugin
        FilePickerPlugin.register(this, flutterEngine.dartExecutor.binaryMessenger)

        // Start and bind the transfer service
        val intent = Intent(this, RecpyService::class.java)
        startForegroundService(intent)
        bindService(intent, connection, Context.BIND_AUTO_CREATE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        ActivityResultRegistry.dispatch(this, requestCode, resultCode, data)
    }

    override fun onDestroy() {
        if (serviceBound) {
            unbindService(connection)
            serviceBound = false
        }
        ActivityResultRegistry.unregister(this)
        super.onDestroy()
    }
}
