package com.abomis.camera_kit_plus

import CameraKitPlusView
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec


class CameraKitPlusViewFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        // Pass the messenger to the NativeCameraView so that it can create a MethodChannel
        return CameraKitPlusView(context, messenger)
    }
}
