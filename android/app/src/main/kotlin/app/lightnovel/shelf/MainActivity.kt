package app.lightnovel.shelf

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val READER_VOLUME_KEY_CHANNEL = "app.lightnovel.shelf/reader_volume_keys"
    }

    private lateinit var readerVolumeKeyChannel: MethodChannel
    private var readerVolumeKeyPagingEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readerVolumeKeyChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            READER_VOLUME_KEY_CHANNEL,
        )
        readerVolumeKeyChannel.setMethodCallHandler { call, result ->
            if (call.method != "setEnabled") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            readerVolumeKeyPagingEnabled = call.arguments as? Boolean ?: false
            result.success(null)
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!readerVolumeKeyPagingEnabled) return super.dispatchKeyEvent(event)
        val key = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> "up"
            KeyEvent.KEYCODE_VOLUME_DOWN -> "down"
            else -> return super.dispatchKeyEvent(event)
        }
        if (event.action == KeyEvent.ACTION_DOWN) {
            readerVolumeKeyChannel.invokeMethod("onVolumeKey", key)
        }
        return true
    }
}
