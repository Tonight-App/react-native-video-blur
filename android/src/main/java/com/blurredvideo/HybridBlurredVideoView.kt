package com.blurredvideo

import android.content.Context
import android.graphics.Color
import android.graphics.RenderEffect
import android.graphics.Shader
import android.net.Uri
import android.os.Build
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import coil.load
import com.margelo.nitro.NitroModules
import com.margelo.nitro.blurredvideo.HybridBlurredVideoViewSpec

class HybridBlurredVideoView : HybridBlurredVideoViewSpec() {

    private val context: Context =
        NitroModules.applicationContext
            ?: throw IllegalStateException("Nitro applicationContext missing")

    private val container = FrameLayout(context).apply {
        clipChildren = true
        clipToPadding = true
        setBackgroundColor(Color.BLACK)
    }

    override val view: View get() = container

    private var player: ExoPlayer? = null
    private var surfaceView: SurfaceView? = null

    private val thumbnailView = ImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER_CROP
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
    }

    init {
        container.addView(thumbnailView)
    }

    // Props

    override var source: String = ""
        set(value) {
            if (field != value) {
                field = value
                loadVideo()
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
            applyBlur()
        }

    override var thumbnailSource: String = ""
        set(value) {
            field = value
            loadThumbnail()
        }

    override var rotation: Double = 0.0
        set(value) {
            field = value
            surfaceView?.rotation = value.toFloat()
        }

    private fun loadVideo() {
        player?.release()
        player = null
        surfaceView?.let { container.removeView(it) }
        surfaceView = null

        if (source.isEmpty()) return

        val sv = SurfaceView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        container.addView(sv, 0)
        surfaceView = sv

        if (rotation == 90.0) sv.rotation = 90f

        val exo = ExoPlayer.Builder(context).build().apply {
            setVideoSurfaceView(sv)
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
        applyBlur()

        if (!paused) exo.play()
    }

    private fun applyBlur() {
        val sv = surfaceView ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            sv.setRenderEffect(
                RenderEffect.createBlurEffect(
                    blurRadius.toFloat(),
                    blurRadius.toFloat(),
                    Shader.TileMode.CLAMP
                )
            )
        }
    }

    private fun loadThumbnail() {
        if (thumbnailSource.isEmpty()) return
        thumbnailView.alpha = 1f
        thumbnailView.visibility = View.VISIBLE
        thumbnailView.load(thumbnailSource)
    }

    override fun dispose() {
        player?.release()
        player = null
        super.dispose()
    }
}
