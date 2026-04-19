package com.margelo.nitro.blurredvideo

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Color
import android.graphics.RenderEffect
import android.graphics.Shader
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import coil.load
import com.facebook.react.uimanager.ThemedReactContext
import java.util.UUID
import java.util.concurrent.Executors

class HybridBlurredVideoView(reactContext: ThemedReactContext) : HybridBlurredVideoViewSpec() {

    private val context: Context = reactContext

    private val container = FrameLayout(context).apply {
        clipChildren = true
        clipToPadding = true
        setBackgroundColor(Color.BLACK)
    }

    override val view: View get() = container

    private var player: ExoPlayer? = null
    private var textureView: TextureView? = null

    private val thumbnailView = ImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER_CROP
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var loadedSource: String? = null
    private var extractedSource: String? = null
    private var extractionToken: UUID? = null

    // Blur animation state
    private var blurAnimator: ValueAnimator? = null
    private var currentAppliedRadius: Float = 7f

    init {
        container.addView(thumbnailView)
    }

    // Props

    override var source: String = ""
        set(value) {
            if (field != value) {
                field = value
                reconcile()
            }
        }

    override var paused: Boolean = true
        set(value) {
            field = value
            if (value) player?.pause() else player?.play()
        }

    override var looping: Boolean = false
        set(value) {
            field = value
            player?.repeatMode =
                if (value) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
        }

    override var blurRadius: Double = 7.0
        set(value) {
            field = value
            animateBlurTo(value.toFloat())
        }

    override var thumbnailSource: String = ""
        set(value) {
            if (field != value) {
                field = value
                loadRemoteThumbnail()
            }
        }

    override var enableThumbnail: Boolean = false
        set(value) {
            if (field != value) {
                field = value
                reconcile()
            }
        }

    override var showVideo: Boolean = true
        set(value) {
            if (field != value) {
                field = value
                reconcile()
            }
        }

    override var rotation: Double = 0.0
        set(value) {
            field = value
            textureView?.rotation = value.toFloat()
        }

    private fun reconcile() {
        if (showVideo) {
            if (loadedSource != source) loadVideo()
        } else {
            unloadVideo()
        }

        if (enableThumbnail
            && thumbnailSource.isEmpty()
            && source.isNotEmpty()
            && extractedSource != source
        ) {
            extractThumbnailFromSource()
        }
    }

    private fun unloadVideo() {
        player?.release()
        player = null
        textureView?.let { container.removeView(it) }
        textureView = null
        loadedSource = null
        thumbnailView.alpha = 1f
        thumbnailView.visibility = View.VISIBLE
    }

    private fun loadVideo() {
        unloadVideo()
        if (source.isEmpty()) return
        loadedSource = source

        val tv = TextureView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            isOpaque = false
        }
        container.addView(tv, 0)
        textureView = tv

        if (rotation == 90.0) tv.rotation = 90f

        val exo = ExoPlayer.Builder(context).build().apply {
            setVideoTextureView(tv)
            repeatMode =
                if (looping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            volume = 0f
            setMediaItem(MediaItem.fromUri(Uri.parse(source)))
            prepare()
        }

        exo.addListener(object : Player.Listener {
            override fun onRenderedFirstFrame() {
                thumbnailView.animate()
                    .alpha(0f)
                    .setStartDelay(100)
                    .setDuration(300)
                    .withEndAction { thumbnailView.visibility = View.GONE }
                    .start()
            }
        })

        player = exo
        applyBlurInternal(currentAppliedRadius)

        if (!paused) exo.play()
    }

    private fun animateBlurTo(target: Float) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { animateBlurTo(target) }
            return
        }
        blurAnimator?.cancel()
        val start = currentAppliedRadius
        if (start == target) {
            applyBlurInternal(target)
            return
        }
        blurAnimator = ValueAnimator.ofFloat(start, target).apply {
            duration = 1000
            interpolator = LinearInterpolator()
            addUpdateListener { anim ->
                val r = anim.animatedValue as Float
                currentAppliedRadius = r
                applyBlurInternal(r)
            }
            start()
        }
    }

    private fun applyBlurInternal(radius: Float) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { applyBlurInternal(radius) }
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val effect = if (radius > 0f) {
            RenderEffect.createBlurEffect(radius, radius, Shader.TileMode.CLAMP)
        } else null
        // Apply once on the container — blurs video + thumbnail together in a single pass.
        container.setRenderEffect(effect)
    }

    private fun loadRemoteThumbnail() {
        if (thumbnailSource.isEmpty()) return
        val videoAlreadyRendered = thumbnailView.visibility == View.GONE
        if (!videoAlreadyRendered) {
            thumbnailView.alpha = 1f
            thumbnailView.visibility = View.VISIBLE
        }
        thumbnailView.load(thumbnailSource)
    }

    private fun extractThumbnailFromSource() {
        val src = source
        extractedSource = src

        // Cache hit → paint synchronously, no flicker.
        VideoThumbnailExtractor.cachedBitmap(context, src, 100, 512)?.let {
            thumbnailView.setImageBitmap(it)
            return
        }

        val videoAlreadyRendered = thumbnailView.visibility == View.GONE
        if (!videoAlreadyRendered) {
            thumbnailView.alpha = 1f
            thumbnailView.visibility = View.VISIBLE
        }

        val token = UUID.randomUUID()
        extractionToken = token
        extractorExecutor.execute {
            val bmp = try {
                VideoThumbnailExtractor.extract(context, src, 100, 512)
            } catch (_: Throwable) {
                return@execute
            }
            mainHandler.post {
                if (extractionToken != token) return@post
                if (thumbnailView.visibility == View.GONE) return@post
                thumbnailView.setImageBitmap(bmp)
            }
        }
    }

    override fun dispose() {
        blurAnimator?.cancel()
        blurAnimator = null
        player?.release()
        player = null
        super.dispose()
    }

    companion object {
        private val extractorExecutor = Executors.newSingleThreadExecutor()
    }
}
