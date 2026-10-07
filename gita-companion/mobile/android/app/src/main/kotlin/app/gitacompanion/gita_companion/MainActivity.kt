package app.gitacompanion.gita_companion

import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

// AudioServiceActivity keeps the Flutter engine shared with the background
// audio service, so listening continues when the app is in the background.
class MainActivity : AudioServiceActivity() {
    private val codecThread = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Speech compression for the audio cache (lib/core/audio/compressor.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.gitacompanion/audio_codec")
            .setMethodCallHandler { call, result ->
                if (call.method != "wavToM4a") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val input = call.argument<String>("input")
                val output = call.argument<String>("output")
                val bitrate = call.argument<Int>("bitrate") ?: 40000
                if (input == null || output == null) {
                    result.error("bad_args", "input and output are required", null)
                    return@setMethodCallHandler
                }
                // Encoding takes a moment per chunk: never on the UI thread.
                codecThread.execute {
                    try {
                        WavToAac.convert(input, output, bitrate)
                        main.post { result.success(null) }
                    } catch (e: Exception) {
                        java.io.File(output).delete()
                        main.post { result.error("encode_failed", e.message, null) }
                    }
                }
            }
    }
}
