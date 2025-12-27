package com.abomis.camera_kit_plus

import android.content.Context
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import android.view.View

class TestView(context: Context, messenger: BinaryMessenger, plugin: CameraKitPlusPlugin) : FrameLayout(context), PlatformView {
    override fun getView(): View {
        return this
    }
    override fun dispose() {}
}
