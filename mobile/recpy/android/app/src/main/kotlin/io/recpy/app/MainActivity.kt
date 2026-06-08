package io.recpy.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FilePickerPlugin.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        ActivityResultRegistry.dispatch(this, requestCode, resultCode, data)
    }

    override fun onDestroy() {
        ActivityResultRegistry.unregister(this)
        super.onDestroy()
    }
}
