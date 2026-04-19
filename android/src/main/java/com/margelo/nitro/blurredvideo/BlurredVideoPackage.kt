package com.margelo.nitro.blurredvideo

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager
import com.margelo.nitro.blurredvideo.views.HybridBlurredVideoViewManager

class BlurredVideoPackage : ReactPackage {
    init {
        // Loads libBlurredVideo.so, which registers all HybridObjects
        // (VideoThumbnailGenerator, BlurredVideoView) in the Nitro registry.
        BlurredVideoOnLoad.initializeNative()
    }

    override fun createNativeModules(
        reactContext: ReactApplicationContext
    ): List<NativeModule> = emptyList()

    override fun createViewManagers(
        reactContext: ReactApplicationContext
    ): List<ViewManager<*, *>> = listOf(HybridBlurredVideoViewManager())
}
