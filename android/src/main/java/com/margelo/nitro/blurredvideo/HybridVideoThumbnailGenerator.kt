package com.margelo.nitro.blurredvideo

import android.content.Context
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import kotlin.math.max

@DoNotStrip
class HybridVideoThumbnailGenerator : HybridVideoThumbnailGeneratorSpec() {

    private val context: Context =
        NitroModules.applicationContext
            ?: throw IllegalStateException("Nitro applicationContext missing")

    override fun generateThumbnail(
        videoPath: String,
        timeMs: Double,
        maxSize: Double
    ): Promise<String> = Promise.async {
        val t = max(timeMs.toInt(), 0)
        val s = max(maxSize.toInt(), 64)
        VideoThumbnailExtractor.extract(context, videoPath, t, s)
        "file://${VideoThumbnailExtractor.cachedFile(context, videoPath, t, s).absolutePath}"
    }
}
