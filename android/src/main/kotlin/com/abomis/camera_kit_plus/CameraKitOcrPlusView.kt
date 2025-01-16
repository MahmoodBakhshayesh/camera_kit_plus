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
import androidx.annotation.OptIn
import androidx.camera.core.AspectRatio
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.abomis.camera_kit_plus.Classes.CornerPointModel
import com.abomis.camera_kit_plus.Classes.LineModel
import com.google.gson.Gson
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.platform.PlatformView
import java.util.Objects
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class CameraKitOcrPlusView(context: Context, messenger: BinaryMessenger) : FrameLayout(context), PlatformView, MethodCallHandler {
    private val methodChannel = MethodChannel(messenger, "camera_kit_plus")
    private lateinit var previewView: PreviewView
    private lateinit var linearLayout: FrameLayout
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private lateinit var textScanner: TextRecognizer
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

        textScanner = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)


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
                        imageAnalysis
                )
            } catch (exc: Exception) {
                Log.e("CameraX", "Use case binding failed", exc)
            }
        }, ContextCompat.getMainExecutor(context))
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
    @OptIn(ExperimentalGetImage::class)
    private fun processImageProxy(imageProxy: ImageProxy) {

        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            textScanner.process(image)
                    .addOnSuccessListener { text ->
                        if (text.text.trim { it <= ' ' }.isEmpty()) {
                        } else {
                            Log.println(Log.ASSERT,"block count",text.textBlocks.count().toString());
                            val lineModels: MutableList<LineModel> = ArrayList<LineModel>()

                            for (b in text.textBlocks) {
                                Log.println(Log.ASSERT,"block lines count",b.lines.count().toString());
                                for (line in b.lines) {
                                    Log.println(Log.ASSERT,"dasd",line.text);
                                    val lineModel: LineModel = LineModel(line.text)
                                    for (p in Objects.requireNonNull<Array<Point>?>(line.cornerPoints)) {
                                        lineModel.cornerPoints.add(CornerPointModel(p.x.toFloat(), p.y.toFloat()))
                                        lineModel.text = line.text;
                                    }
                                    Log.println(Log.ASSERT,"dasd",lineModel.text);
                                    lineModels.add(lineModel)
                                }
                            }
                            Log.println(Log.ASSERT,"dasd",lineModels.count().toString());

                            val gson: Gson = Gson()
                            gson.toJson(lineModels)

                            val map: MutableMap<String, Any> = HashMap()
                            map["text"] = text.text
                            map["lines"] = lineModels
                            map["path"] = ""
                            map["orientation"] = 0
                            methodChannel.invokeMethod("onTextRead", Gson().toJson(map))
                        }
                    }
                    .addOnFailureListener {
                        Log.e("Text", "Failed to scan barcode", it)
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
            "changeFlashMode" -> {
                val flashModeID = call.argument<Int>("flashModeID")!!
                changeFlashMode(flashModeID,result)
            }

            "switchCamera" -> {
                val cameraID = call.argument<Int>("cameraID")!!
                switchCamera(cameraID,result)
            }

            "pauseCamera" -> pauseCamera(result)
            "resumeCamera" -> resumeCamera(result)
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
        if (textScanner != null) {
            textScanner.close()
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
