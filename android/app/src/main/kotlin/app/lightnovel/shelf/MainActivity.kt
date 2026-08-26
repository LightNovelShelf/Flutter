package app.lightnovel.shelf

import android.os.Bundle

import android.view.KeyEvent
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    private companion object {
        const val READER_VOLUME_KEY_CHANNEL = "app.lightnovel.shelf/reader_volume_keys"
    }

    private var readerVolumeKeyChannel: MethodChannel? = null
    private var readerVolumeKeyPagingEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readerVolumeKeyPagingEnabled = false
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            READER_VOLUME_KEY_CHANNEL,
        )
        channel.setMethodCallHandler { call, result ->
            if (call.method != "setEnabled") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            readerVolumeKeyPagingEnabled = call.arguments as? Boolean ?: false
            result.success(null)
        }
        readerVolumeKeyChannel = channel
        // 引擎可能接到新的 Activity 上，此时开关状态刚归零而 Dart 侧仍记着旧值，
        // 要它重发一次，否则阅读器里的音量键会一直不响应。
        channel.invokeMethod("resync", null)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        readerVolumeKeyChannel?.setMethodCallHandler(null)
        readerVolumeKeyChannel = null
        readerVolumeKeyPagingEnabled = false
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val channel = readerVolumeKeyChannel
        if (!readerVolumeKeyPagingEnabled || channel == null) {
            return super.dispatchKeyEvent(event)
        }
        val key = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> "up"
            KeyEvent.KEYCODE_VOLUME_DOWN -> "down"
            else -> return super.dispatchKeyEvent(event)
        }
        // 音量键按住会自动重复上报 ACTION_DOWN，只认第一次，否则长按就一路翻到章末。
        // ACTION_UP 也要吞掉，只拦 ACTION_DOWN 的话音量不变但系统音量条会闪一下。
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            channel.invokeMethod("onVolumeKey", key)
        }
        return true
    }
}
