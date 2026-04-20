package com.margelo.nitro.blurredvideo

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Color
import android.graphics.Matrix
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
import androidx.media3.common.VideoSize
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

    // Video intrinsic size, used to compute cover (center-crop) transform.
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0

    // Perceptual scale for RenderEffect blur radius (px). Android's RenderEffect
    // blur is weaker than iOS CIGaussianBlur at the same nominal value, and the
    // prop comes in as density-independent. Multiply by density × 2.5 so a prop
    // of ~7 produces a clearly visible frosted-glass effect.
    private val blurScale: Float = context.resources.displayMetrics.density * 2.5f

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
            // Declarative: the player auto-plays when it reaches STATE_READY,
            // and auto-pauses otherwise. Avoids races where explicit play()
            // is called before the player is prepared.
            player?.playWhenReady = !value
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

    override var showVideo: Boolean = false
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
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { unloadVideo() }
            return
        }
        player?.release()
        player = null
        textureView?.let { container.removeView(it) }
        textureView = null
        videoWidth = 0
        videoHeight = 0
        loadedSource = null
        // Keep whatever bitmap is already on the ImageView — it's the starting
        // thumbnail (either extracted or provided). We do NOT snapshot the
        // last video frame: user-facing intent is that the video restarts
        // from the beginning when this cover becomes active again, and the
        // thumbnail should match that.
        thumbnailView.alpha = 1f
        thumbnailView.visibility = View.VISIBLE
        // Re-apply blur so the thumbnail stays frosted — this is our
        // "paused / off-screen" state, matching iOS.
        applyBlurInternal(currentAppliedRadius)
    }

    private fun loadVideo() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { loadVideo() }
            return
        }
        unloadVideo()
        if (source.isEmpty()) return
        loadedSource = source

        val tv = TextureView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            isOpaque = false
            addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                updateTextureTransform()
            }
        }
        container.addView(tv, 0)
        textureView = tv

        if (rotation == 90.0) tv.rotation = 90f

        val exo = ExoPlayer.Builder(context).build().apply {
            repeatMode =
                if (looping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            volume = 0f
            // Declarative start intent — honoured automatically once the
            // player reaches STATE_READY. Safe to set before prepare().
            playWhenReady = !this@HybridBlurredVideoView.paused
            setMediaItem(MediaItem.fromUri(Uri.parse(source)))
        }
        // Assign the player reference BEFORE any async attachment work, so
        // that prop setters (paused, looping, rotation) arriving during
        // surface-texture setup see a live player instance.
        player = exo

        exo.addListener(object : Player.Listener {
            override fun onRenderedFirstFrame() {
                thumbnailView.animate()
                    .alpha(0f)
                    .setStartDelay(100)
                    .setDuration(300)
                    .withEndAction { thumbnailView.visibility = View.GONE }
                    .start()
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                videoWidth = videoSize.width
                videoHeight = videoSize.height
                updateTextureTransform()
            }
        })

        // ExoPlayer handles both "surface ready now" and "surface ready
        // later" internally — it installs its own SurfaceTextureListener and
        // picks up the surface whenever it arrives. Calling setVideoTextureView
        // from inside a foreign listener callback caused racy attach failures.
        exo.setVideoTextureView(tv)
        exo.prepare()

        applyBlurInternal(currentAppliedRadius)
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
        val scaled = radius * blurScale
        val effect = if (scaled > 0f) {
            RenderEffect.createBlurEffect(scaled, scaled, Shader.TileMode.CLAMP)
        } else null
        // Apply to each pixel-bearing child individually. Applying to the
        // container works in the simple case but occasionally drops the
        // effect on the remaining ImageView when the TextureView is torn
        // down (e.g. during carousel swipes that toggle `showVideo`).
        textureView?.setRenderEffect(effect)
        thumbnailView.setRenderEffect(effect)
    }

    // Center-crop (cover) scaling for the TextureView's SurfaceTexture.
    // TextureView stretches content to view bounds by default; we compute a
    // matrix that scales the larger axis up so one dimension overflows and
    // gets clipped by the container (clipChildren = true).
    private fun updateTextureTransform() {
        val tv = textureView ?: return
        val vw = tv.width
        val vh = tv.height
        if (vw <= 0 || vh <= 0 || videoWidth <= 0 || videoHeight <= 0) return

        val viewAspect = vw.toFloat() / vh.toFloat()
        val videoAspect = videoWidth.toFloat() / videoHeight.toFloat()

        val sx: Float
        val sy: Float
        if (videoAspect > viewAspect) {
            // Video is wider than view — scale X up so height fills, width overflows.
            sx = videoAspect / viewAspect
            sy = 1f
        } else {
            // Video is taller than view — scale Y up so width fills, height overflows.
            sx = 1f
            sy = viewAspect / videoAspect
        }

        val matrix = Matrix().apply {
            setScale(sx, sy, vw / 2f, vh / 2f)
        }
        tv.setTransform(matrix)
        tv.invalidate()
    }

    private fun loadRemoteThumbnail() {
        if (thumbnailSource.isEmpty()) return
        val videoAlreadyRendered = thumbnailView.visibility == View.GONE
        if (!videoAlreadyRendered) {
            thumbnailView.alpha = 1f
            thumbnailView.visibility = View.VISIBLE
        }
        thumbnailView.load(thumbnailSource)
        applyBlurInternal(currentAppliedRadius)
    }

    private fun extractThumbnailFromSource() {
        val src = source
        extractedSource = src

        // Cache hit → paint synchronously, no flicker.
        VideoThumbnailExtractor.cachedBitmap(context, src, 100, 512)?.let {
            thumbnailView.setImageBitmap(it)
            applyBlurInternal(currentAppliedRadius)
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
                // Set the bitmap unconditionally — even if the thumbnail is
                // currently hidden behind the video. We want it ready so that
                // when `showVideo` flips to false (e.g. carousel swipe), the
                // ImageView already has content to display (blurred) instead
                // of going black.
                thumbnailView.setImageBitmap(bmp)
                applyBlurInternal(currentAppliedRadius)
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