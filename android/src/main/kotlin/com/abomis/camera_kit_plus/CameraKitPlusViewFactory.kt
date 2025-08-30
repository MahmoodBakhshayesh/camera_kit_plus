package com.abomis.camera_kit_plus

import CameraKitPlusView
//import CameraView2
import android.content.Context
import android.util.Log
import androidx.camera.lifecycle.ProcessCameraProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec

class CameraKitPlusViewFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, id: Int, args: Any?): PlatformView {
//        val isCameraXSupported = isCameraXSupported(context)
//        if(isCameraXSupported){
            return CameraKitPlusView(context, messenger)
//        }
//         Pass the messenger to the NativeCameraView so that it can create a MethodChannel
//        return CameraView2(context, messenger)
    }

    private fun isCameraXSupported(context: Context): Boolean {
        return try {
            val cameraProvider = ProcessCameraProvider.getInstance(context)
            cameraProvider.get() // Trying to get the camera provider, which will initialize CameraX
            true
        } catch (e: Exception) {
            Log.e("CameraXCheck", "CameraX is not supported: ${e.message}")
            false
        }
    }
}
