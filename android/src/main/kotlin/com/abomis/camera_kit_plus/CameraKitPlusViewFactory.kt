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
//
//class CameraKitPlusViewFactory(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
//    override fun create(context: Context, id: Int, args: Any?): PlatformView {
//        return CameraKitPlusView(context,fli)
//    }
//}


//class NativeCameraView(context: Context) : FrameLayout(context), PlatformView {
//    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
//
//    val REQUEST_CAMERA_PERMISSION = 1001
//
//
//    init {
//        // Check and request camera permission
//        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
//            // Permission is not granted, request the permission
//            ActivityCompat.requestPermissions(
//                    getActivity(context)!!,
//                    arrayOf(Manifest.permission.CAMERA),
//                    REQUEST_CAMERA_PERMISSION
//            )
//        } else {
//            // Permission already granted, proceed with camera setup
//            setupCamera()
//        }
//    }
//
//    private fun setupCamera() {
//        // Create a camera preview view
//        val previewView = androidx.camera.view.PreviewView(context).apply {
//            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
//        }
//
//        // Add the camera preview to the view hierarchy
//        addView(previewView)
//
//        // Get the correct LifecycleOwner from the context
//        val activity = getActivity(context)
//        val lifecycleOwner = activity as LifecycleOwner
//
//        // Set up CameraX and barcode scanning
//        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
//        cameraProviderFuture.addListener({
//            val cameraProvider = cameraProviderFuture.get()
//
//            // Set up the preview use case
//            val preview = Preview.Builder().build().also {
//                it.setSurfaceProvider(previewView.surfaceProvider)
//            }
//
//            // Set up the analysis use case for barcode scanning
//            val imageAnalysis = ImageAnalysis.Builder()
//                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
//                    .build()
//
//            // Select the back camera as default
//            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
//
//            // Unbind all use cases before rebinding
//            cameraProvider.unbindAll()
//
//            try {
//                // Bind use cases to the camera with the LifecycleOwner
//                cameraProvider.bindToLifecycle(
//                        lifecycleOwner,
//                        cameraSelector,
//                        preview,
//                        imageAnalysis
//                )
//            } catch (exc: Exception) {
//                Log.e("CameraX", "Use case binding failed", exc)
//            }
//        }, ContextCompat.getMainExecutor(context))
//    }
//    // Helper function to retrieve the Activity from a given Context
//    private fun getActivity(context: Context): Activity? {
//        var contextTemp = context
//        while (contextTemp is android.content.ContextWrapper) {
//            if (contextTemp is Activity) {
//                return contextTemp
//            }
//            contextTemp = contextTemp.baseContext
//        }
//        return null
//    }
//
//    // PlatformView method implementation
//    override fun getView(): FrameLayout {
//        return this
//    }
//
//    override fun dispose() {
//        cameraExecutor.shutdown()
//    }
//}