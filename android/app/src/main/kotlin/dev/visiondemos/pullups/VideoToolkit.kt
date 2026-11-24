package dev.visiondemos.pullups

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Trims and normalises a clip to 720p / 30 fps H.264 with Media3, so the upload
 * stays small and the model sees frames the app can index one-to-one.
 */
@OptIn(UnstableApi::class)
class VideoToolkit(context: Context, private val channel: MethodChannel) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.visiondemos.pullups/video"
    }

    private val appContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private var transformer: Transformer? = null
    private var pending: MethodChannel.Result? = null
    private var progressPoll: Runnable? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> {
                val path = call.argument<String>("path")
                if (path == null) return VideoProbe.fail(result, "bad_args", "missing path")
                try {
                    result.success(VideoProbe.probe(path))
                } catch (exc: Exception) {
                    VideoProbe.fail(result, "probe_failed", exc.message ?: "could not read clip")
                }
            }

            "transcode" -> transcode(call, result)

            "cancel" -> {
                val active = transformer
                pending?.error("cancelled", "Cancelled", null)
                pending = null
                stopProgress()
                transformer = null
                active?.cancel()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun transcode(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) {
            return VideoProbe.fail(result, "busy", "a clip is already being prepared")
        }
        val input = call.argument<String>("input")!!
        val output = call.argument<String>("output")!!
        if (input.isEmpty() || output.isEmpty()) {
            return VideoProbe.fail(result, "bad_args", "missing input or output")
        }
        val startMs = (call.argument<Number>("startMs") ?: 0).toLong().coerceAtLeast(0)
        val endMs = (call.argument<Number>("endMs") ?: 0).toLong()
        val height = (call.argument<Number>("height") ?: 720).toInt()
        val fps = (call.argument<Number>("fps") ?: 30).toInt()

        val outputFile = File(output)
        outputFile.parentFile?.mkdirs()
        outputFile.delete()

        pending = result
        try {
            val clipping = MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(startMs)
                .apply { if (endMs > startMs) setEndPositionMs(endMs) }
                .build()

            val mediaItem = MediaItem.Builder()
                .setUri(Uri.fromFile(File(input)))
                .setClippingConfiguration(clipping)
                .build()

            val effects = Effects(
                emptyList(),
                listOf<androidx.media3.common.Effect>(Presentation.createForHeight(height)),
            )

            val item = EditedMediaItem.Builder(mediaItem)
                .setRemoveAudio(true)
                .setFrameRate(fps)
                .setEffects(effects)
                .build()

            val sequence = EditedMediaItemSequence.Builder(item).build()
            val composition = Composition.Builder(sequence)
                .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
                .build()

            val listener = object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    if (pending == null) return
                    stopProgress()
                    transformer = null
                    val answer = try {
                        VideoProbe.probe(output)
                    } catch (exc: Exception) {
                        pending = null
                        outputFile.delete()
                        return VideoProbe.fail(result, "probe_failed", exc.message ?: "output unreadable")
                    }
                    pending = null
                    result.success(answer)
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    if (pending == null) return
                    stopProgress()
                    transformer = null
                    pending = null
                    outputFile.delete()
                    result.error(
                        "transcode_failed",
                        exportException.message ?: "could not prepare the clip",
                        null,
                    )
                }
            }

            val built = Transformer.Builder(appContext)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .addListener(listener)
                .build()
            transformer = built
            built.start(composition, output)
            startProgress()
        } catch (exc: Exception) {
            pending = null
            stopProgress()
            result.error("transcode_failed", exc.message ?: "could not prepare the clip", null)
        }
    }

    private fun startProgress() {
        val holder = ProgressHolder()
        val poll = object : Runnable {
            override fun run() {
                val active = transformer ?: return
                val state = active.getProgress(holder)
                if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                    channel.invokeMethod("transcodeProgress", mapOf("percent" to holder.progress))
                }
                if (state != Transformer.PROGRESS_STATE_NOT_STARTED) {
                    main.postDelayed(this, 400)
                }
            }
        }
        progressPoll = poll
        main.postDelayed(poll, 400)
    }

    private fun stopProgress() {
        progressPoll?.let { main.removeCallbacks(it) }
        progressPoll = null
    }
}
