package com.blurredvideo

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

/**
 * Shared fast-path thumbnail extractor used by both the standalone Nitro
 * module and `HybridBlurredVideoView`'s built-in `enableThumbnail` mode.
 * JPEGs land in the app cache dir keyed by (source, timeMs, maxSize) so
 * repeat calls — across view instances and the standalone API — are free.
 */
object VideoThumbnailExtractor {

    fun cachedFile(context: Context, source: String, timeMs: Int, maxSize: Int): File {
        val key = "${source.hashCode()}_${timeMs}_${maxSize}"
        return File(context.cacheDir, "blurvideo-thumb-$key.jpg")
    }

    fun cachedBitmap(context: Context, source: String, timeMs: Int, maxSize: Int): Bitmap? {
        val f = cachedFile(context, source, timeMs, maxSize)
        if (!f.exists()) return null
        return BitmapFactory.decodeFile(f.absolutePath)
    }

    /** Blocking — caller must run on a background thread. */
    fun extract(context: Context, source: String, timeMs: Int, maxSize: Int): Bitmap {
        val outFile = cachedFile(context, source, timeMs, maxSize)
        cachedBitmap(context, source, timeMs, maxSize)?.let { return it }

        val retriever = MediaMetadataRetriever()
        try {
            val uri = Uri.parse(source)
            if (uri.scheme == null || uri.scheme == "file") {
                retriever.setDataSource(uri.path ?: source)
            } else {
                retriever.setDataSource(source, emptyMap())
            }

            val timeUs = max(timeMs * 1000L, 0L)
            val cap = max(maxSize, 64)

            val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(
                    timeUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    cap,
                    cap
                )
            } else {
                retriever.getFrameAtTime(
                    timeUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                )
            } ?: throw RuntimeException("Failed to extract frame at ${timeMs}ms")

            FileOutputStream(outFile).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
            }
            return bitmap
        } finally {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) retriever.close()
                else retriever.release()
            } catch (_: Throwable) {}
        }
    }
}
