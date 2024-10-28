import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Point
import android.util.DisplayMetrics
import android.util.Log
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.annotation.OptIn
import androidx.camera.core.AspectRatio
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.platform.PlatformView
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class CameraKitPlusView(context: Context, messenger: BinaryMessenger) : FrameLayout(context), PlatformView, MethodCallHandler {
    private val methodChannel = MethodChannel(messenger, "camera_kit_plus")
    private lateinit var previewView: PreviewView
    private lateinit var linearLayout: FrameLayout
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private lateinit var barcodeScanner: BarcodeScanner
    private var preview: Preview? = null
    val REQUEST_CAMERA_PERMISSION = 1001

    init {
        linearLayout = getActivity(context)?.let { FrameLayout(it) }!!
        linearLayout.layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT)
        linearLayout.setBackgroundColor(Color.parseColor("#000000"))
        previewView = getActivity(context)?.let { PreviewView(it) }!!
        previewView.layoutParams = LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE

        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                    getActivity(context)!!,
                    arrayOf(Manifest.permission.CAMERA),
                    REQUEST_CAMERA_PERMISSION
            )
        } else {
            setupPreview()
        }
    }


    private fun setupPreview() {
        var displaySize = Point()
        var displaymetrics = DisplayMetrics()
        displaymetrics = context.resources.displayMetrics
        val screenWidth = displaymetrics.widthPixels
        val screenHeight = displaymetrics.heightPixels
        displaySize.x = screenWidth
        displaySize.y = screenHeight
        linearLayout.layoutParams = LayoutParams(displaySize.x, displaySize.y)
        linearLayout.addView(previewView)
        setupCamera()
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        previewView.layout(0, 0, right - left, bottom - top)
    }


    private fun setupCamera() {
        val activity = getActivity(context)
        val lifecycleOwner = activity as LifecycleOwner

        val options = BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS) // Scan all types of barcodes
                .build()
        barcodeScanner = BarcodeScanning.getClient(options)

        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()

            preview = Preview.Builder()
                    .setTargetAspectRatio(AspectRatio.RATIO_16_9)  // Match aspect ratio of PreviewView
                    .build()
                    .also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }

            val imageAnalysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also {
                        it.setAnalyzer(cameraExecutor) { imageProxy ->
                            processImageProxy(imageProxy)
                        }
                    }

            // Select the back camera as default
            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            // Unbind all use cases before rebinding
            cameraProvider.unbindAll()
            preview = Preview.Builder().setTargetAspectRatio(AspectRatio.RATIO_16_9).setTargetRotation(previewView.rotation.toInt()).build()
            preview!!.setSurfaceProvider(previewView.surfaceProvider)
            try {
                cameraProvider.bindToLifecycle(
                        lifecycleOwner,
                        cameraSelector,
                        preview,
                        imageAnalysis
                )
            } catch (exc: Exception) {
                Log.e("CameraX", "Use case binding failed", exc)
            }
        }, ContextCompat.getMainExecutor(context))
    }


//    private fun setupCamera2() {
//        // Create a camera preview view
//        previewView = androidx.camera.view.PreviewView(context).apply {
////            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
//            layoutParams = LayoutParams(
//                    LayoutParams.MATCH_PARENT,  // Make the PreviewView fill the width of the parent
//                    LayoutParams.MATCH_PARENT   // Make the PreviewView fill the height of the parent
//            )
//            scaleType = PreviewView.ScaleType.FILL_CENTER  // Ensure preview fills the entire view
//
//        }
//        previewView.setBackgroundColor(Color.YELLOW)
//        addView(previewView)
//        previewView.scaleType = PreviewView.ScaleType.FILL_CENTER  // This will ensure the preview fills the view
//
//        // Get the correct LifecycleOwner from the context
//        val activity = getActivity(context)
//        val lifecycleOwner = activity as LifecycleOwner
//
//        // Initialize barcode scanner with options
//        val options = BarcodeScannerOptions.Builder()
//                .setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS) // Scan all types of barcodes
//                .build()
//        barcodeScanner = BarcodeScanning.getClient(options)
//
////         Bind camera and start preview
//        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
//        cameraProviderFuture.addListener({
//            val cameraProvider = cameraProviderFuture.get()
//
////            1440 -- 2400
////            val resolution = Size(1440, 2400)
////            val resolution = Size(1920, 1080)
//            // Set up the preview use case
//
//            val preview = Preview.Builder()
//                    .setTargetAspectRatio(AspectRatio.RATIO_16_9)  // Match aspect ratio of PreviewView
//
////                    .setTargetResolution(resolution)
//                    .build()
//                    .also {
//                        it.setSurfaceProvider(previewView.surfaceProvider)
//                    }
//
//            // Set up the analysis use case for barcode scanning
//            val imageAnalysis = ImageAnalysis.Builder()
//                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
////                    .setTargetResolution(resolution)  // Set resolution for preview
//                    .build()
//                    .also {
//                        it.setAnalyzer(cameraExecutor, { imageProxy ->
//                            processImageProxy(imageProxy)
//                        })
//                    }
//
//            // Select the back camera as default
//            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
//
//            // Unbind all use cases before rebinding
//            cameraProvider.unbindAll()
//
//            try {
//                // Bind use cases to camera
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

    private fun getActivity(context: Context): Activity? {
        var contextTemp = context
        while (contextTemp is android.content.ContextWrapper) {
            if (contextTemp is Activity) {
                return contextTemp
            }
            contextTemp = contextTemp.baseContext
        }
        return null
    }


    // Process each frame for barcode scanning
    @OptIn(ExperimentalGetImage::class)
    private fun processImageProxy(imageProxy: ImageProxy) {

        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            barcodeScanner.process(image)
                    .addOnSuccessListener { barcodes ->
                        for (barcode in barcodes) {
                            methodChannel.invokeMethod("onBarcodeScanned", "${barcode.rawValue}")
                        }
                    }
                    .addOnFailureListener {
                        Log.e("Barcode", "Failed to scan barcode", it)
                    }
                    .addOnCompleteListener {
                        imageProxy.close() // Make sure to close the image proxy
                    }
        }
    }

    override fun getView(): FrameLayout {
        return linearLayout
    }

    override fun dispose() {
        cameraExecutor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {

    }
}
