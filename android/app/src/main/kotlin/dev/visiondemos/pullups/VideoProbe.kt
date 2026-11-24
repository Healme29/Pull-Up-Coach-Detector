package dev.visiondemos.pullups

import android.media.MediaMetadataRetriever
import io.flutter.plugin.common.MethodChannel

/** Reads the bits of a clip Flutter cannot: duration, fps, frame count, rotation. */
object VideoProbe {
    fun probe(path: String): Map<String, Any?> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val width = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            val height = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            val rotation = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            val captureFps = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
                ?.toDoubleOrNull()
            val frameCount = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)
                ?.toLongOrNull() ?: 0L

            val fps = captureFps
                ?: if (durationMs > 0 && frameCount > 0) {
                    frameCount.toDouble() * 1000.0 / durationMs
                } else {
                    30.0
                }

            return mapOf(
                "path" to path,
                "durationMs" to durationMs,
                "width" to width,
                "height" to height,
                "rotation" to rotation,
                "fps" to fps,
                "frameCount" to frameCount,
            )
        } finally {
            retriever.release()
        }
    }

    fun fail(result: MethodChannel.Result, code: String, message: String) {
        result.error(code, message, null)
    }
}
