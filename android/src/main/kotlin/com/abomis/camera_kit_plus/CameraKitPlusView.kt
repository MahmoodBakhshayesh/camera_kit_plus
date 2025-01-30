import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Point
import android.os.Build
import android.util.DisplayMetrics
import android.util.Log
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.camera.core.AspectRatio
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.abomis.camera_kit_plus.Classes.BarcodeData
import com.google.gson.Gson
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
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class CameraKitPlusView(context: Context, messenger: BinaryMessenger) : FrameLayout(context), PlatformView, MethodCallHandler {
    private val methodChannel = MethodChannel(messenger, "camera_kit_plus")
    private lateinit var previewView: PreviewView
    private lateinit var linearLayout: FrameLayout
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var imageCapture: ImageCapture? = null

    private lateinit var barcodeScanner: BarcodeScanner
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var cameraSelector: CameraSelector? = null

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
        methodChannel.setMethodCallHandler(this)
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
        setupCameraSelector()
        setupCamera()
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        previewView.layout(0, 0, right - left, bottom - top)
    }

    private  fun setupCameraSelector(){
        cameraSelector =  CameraSelector.DEFAULT_BACK_CAMERA
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
            cameraProvider = cameraProviderFuture.get()

            preview = Preview.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_16_9)
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

            imageCapture = ImageCapture.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_16_9)
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                .build()

            // Select the back camera as default
//            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            // Unbind all use cases before rebinding
            cameraProvider?.unbindAll()
            preview = Preview.Builder().setTargetAspectRatio(AspectRatio.RATIO_16_9).setTargetRotation(previewView.rotation.toInt()).build()
            preview!!.setSurfaceProvider(previewView.surfaceProvider)
            try {
                camera = cameraProvider?.bindToLifecycle(
                    lifecycleOwner,
                    cameraSelector!!,
                    preview,
                    imageCapture,
                    imageAnalysis
                )
            } catch (exc: Exception) {
                Log.e("CameraX", "Use case binding failed", exc)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun takePicture(result: MethodChannel.Result) {
        val file = File(context.cacheDir, "captured_image_${System.currentTimeMillis()}.jpg")

        val outputOptions = ImageCapture.OutputFileOptions.Builder(file).build()

        imageCapture?.takePicture(outputOptions, ContextCompat.getMainExecutor(context),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                    result.success(file.absolutePath) // Return image path to Flutter
                }

                override fun onError(exception: ImageCaptureException) {
                    result.error("IMAGE_CAPTURE_FAILED", "Failed to capture image", exception.message)
                }
            })
    }



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
    private fun processImageProxy(imageProxy: ImageProxy) {

        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            barcodeScanner.process(image)
                .addOnSuccessListener { barcodes ->
                    for (barcode in barcodes) {
                        methodChannel.invokeMethod("onBarcodeScanned", "${barcode.rawValue}")
                        methodChannel.invokeMethod("onBarcodeDataScanned", Gson().toJson(BarcodeData(barcode)))

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
        when (call.method) {
            "getPlatformVersion" -> result.success("Android" + Build.VERSION.RELEASE)
//            "getCameraPermission" -> getCameraPermission(result)
//            "initCamera" -> {
//                val initFlashModeID = call.argument<Int>("initFlashModeID")!!
//                val fill = java.lang.Boolean.TRUE == call.argument("fill")
//                val barcodeTypeID = call.argument<Int>("barcodeTypeID")!!
//                val modeID = call.argument<Int>("modeID")!!
//                val cameraID = call.argument<Int>("cameraTypeID")!!
//                initCamera(initFlashModeID, fill, barcodeTypeID, cameraID, modeID)
//            }

            "changeFlashMode" -> {
                val flashModeID = call.argument<Int>("flashModeID")!!
                changeFlashMode(flashModeID,result)
            }

            "switchCamera" -> {
                val cameraID = call.argument<Int>("cameraID")!!
                switchCamera(cameraID,result)
            }

//            "changeCameraVisibility" -> {
//                val visibility = java.lang.Boolean.TRUE == call.argument("visibility")
//                changeCameraVisibility(visibility)
//            }

            "pauseCamera" -> pauseCamera(result)
            "resumeCamera" -> resumeCamera(result)
            "takePicture" -> {
                takePicture(result)
            }

//            "processImageFromPath" -> {
//                val imgPath = call.argument<String>("path")
//                processImageFromPath(imgPath, result)
//            }

            "dispose" -> dispose()
            else -> result.notImplemented()
        }
    }

    private fun switchCamera(cameraID: Int, result: MethodChannel.Result) {
        if(cameraID == 0){
            cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
            setupCamera()

        }else{
            cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA
            setupCamera()

        }
    }

    private fun resumeCamera(result: MethodChannel.Result) {
        setupCamera()
    }

    private fun pauseCamera(result: MethodChannel.Result) {
        cameraProvider?.unbindAll()
        if (barcodeScanner != null) {
            barcodeScanner.close()
//            barcodeScanner = null
        }

    }

    private fun getFlashMode(flashModeID: Int): Int {
        return when (flashModeID) {
            1 -> ImageCapture.FLASH_MODE_ON
            0 -> ImageCapture.FLASH_MODE_OFF
            else -> ImageCapture.FLASH_MODE_AUTO
        }
    }

    private fun changeFlashMode(flashModeID: Int, result: MethodChannel.Result) {
        if (camera != null) {
            camera!!.getCameraControl().enableTorch(flashModeID == 1)
        }
    }
}
