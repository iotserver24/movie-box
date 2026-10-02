package dev.r3ap3r.movie_box_app

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.r3ap3r.movie_box_app/media")
            .setMethodCallHandler { call, result ->
                if (call.method != "thumbnail") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.arguments as? String
                if (path == null) {
                    result.error("INVALID_PATH", "Video path is required", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val source = File(path).canonicalFile
                        val appDirectory = filesDir.parentFile!!.canonicalFile
                        if (!source.path.startsWith("${appDirectory.path}/") || !source.isFile) {
                            throw IllegalArgumentException("Video is not stored in this app")
                        }
                        val destination = File("${source.path}.preview.jpg")
                        if (!destination.exists()) {
                            val retriever = MediaMetadataRetriever()
                            try {
                                retriever.setDataSource(source.path)
                                val durationMs = retriever.extractMetadata(
                                    MediaMetadataRetriever.METADATA_KEY_DURATION
                                )?.toLongOrNull() ?: 0L
                                val previewUs = if (durationMs > 0) durationMs * 250L else 120_000_000L
                                val frame = retriever.getFrameAtTime(
                                    previewUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                                ) ?: throw IllegalStateException("No video frame available")
                                val width = 480
                                val height = (frame.height * width / frame.width).coerceAtLeast(1)
                                val scaled = Bitmap.createScaledBitmap(frame, width, height, true)
                                FileOutputStream(destination).use { scaled.compress(Bitmap.CompressFormat.JPEG, 82, it) }
                                if (scaled !== frame) scaled.recycle()
                                frame.recycle()
                            } finally {
                                retriever.release()
                            }
                        }
                        runOnUiThread { result.success(destination.path) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("THUMBNAIL_FAILED", error.message, null) }
                    }
                }.start()
            }
    }
}
