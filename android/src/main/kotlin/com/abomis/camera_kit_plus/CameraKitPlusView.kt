import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Point
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.os.Build
import android.util.DisplayMetrics
import android.util.Log
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.annotation.OptIn
import androidx.annotation.RequiresApi
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.Observer
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
import io.flutter.plugin.platform.PlatformView
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

class CameraKitPlusView(context: Context, messenger: BinaryMessenger) :
    FrameLayout(context), PlatformView, MethodChannel.MethodCallHandler {

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

    private val barcodeTimestamps = mutableMapOf<String, MutableList<Long>>()
    private val detectionWindowMs = 200L
    private val detectionThreshold = 4

    // ====== Zoom state / gestures ======
    private var scaleDetector: ScaleGestureDetector? = null
    private var gestureDetector: GestureDetector? = null
    private var lastGestureZoomRatio: Float = 1f
    private var tapDetector: android.view.GestureDetector? = null
    private var pinchZoomRatio: Float = 1f

    // ====== Macro bias ======
    private var macroEnabled: Boolean = false
    private var pinchStartLinearZoom = 0f

    init {
        linearLayout = getActivity(context)?.let { FrameLayout(it) }!!
        linearLayout.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.MATCH_PARENT
        )
        linearLayout.setBackgroundColor(Color.parseColor("#000000"))

        previewView = getActivity(context)?.let { PreviewView(it) }!!
        previewView.layoutParams =
            LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE

        methodChannel.setMethodCallHandler(this)

        attachPinchToZoom()
        attachDoubleTapReset()

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

    @RequiresApi(Build.VERSION_CODES.N)
    private fun setupPreview() {
        val displaySize = Point()
        val displaymetrics = context.resources.displayMetrics
        displaySize.x = displaymetrics.widthPixels
        displaySize.y = displaymetrics.heightPixels

        linearLayout.layoutParams = LayoutParams(displaySize.x, displaySize.y)
        linearLayout.addView(previewView)
        setupCameraSelector()
        setupCamera()
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        previewView.layout(0, 0, right - left, bottom - top)
    }

    private fun setupCameraSelector() {
        cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
    }

    @RequiresApi(Build.VERSION_CODES.N)
    @OptIn(ExperimentalCamera2Interop::class)
    private fun bindUseCases(lifecycleOwner: LifecycleOwner) {
        val provider = cameraProvider ?: return

        // --- Preview with optional Macro scene mode via Camera2Interop
        val previewBuilder = Preview.Builder()
            .setTargetAspectRatio(AspectRatio.RATIO_16_9)

        // Apply MACRO scene mode if requested (best-effort)
        if (macroEnabled) {
            try {
                val ext = Camera2Interop.Extender(previewBuilder)
                ext.setCaptureRequestOption(
                    CaptureRequest.CONTROL_MODE,
                    CameraMetadata.CONTROL_MODE_USE_SCENE_MODE
                )
                ext.setCaptureRequestOption(
                    CaptureRequest.CONTROL_SCENE_MODE,
                    CameraMetadata.CONTROL_AF_MODE_MACRO
                )
                ext.setCaptureRequestOption(
                    CaptureRequest.CONTROL_AF_MODE,
                    CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
                )
            } catch (t: Throwable) {
                Log.w("CameraX", "Macro interop (Preview) not applied: ${t.message}")
            }
        }

        preview = previewBuilder.build().also {
            it.setSurfaceProvider(previewView.surfaceProvider)
        }

        // --- ImageAnalysis (barcode)
        val analysisBuilder = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
        if (macroEnabled) {
            try {
                val ext = Camera2Interop.Extender(analysisBuilder)
                ext.setCaptureRequestOption(
                    CaptureRequest.CONTROL_MODE,
                    CameraMetadata.CONTROL_MODE_USE_SCENE_MODE
                )
                ext.setCaptureRequestOption(
                    CaptureRequest.CONTROL_SCENE_MODE,
                    CameraMetadata.CONTROL_AF_MODE_MACRO
                )
                ext.setCaptureRequestOption(
                    CaptureRequest.CONTROL_AF_MODE,
                    CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
                )
            } catch (t: Throwable) {
                Log.w("CameraX", "Macro interop (Analysis) not applied: ${t.message}")
            }
        }
        val imageAnalysis = analysisBuilder.build().also { analysis ->
            analysis.setAnalyzer(cameraExecutor) { imageProxy ->
                processImageProxy(imageProxy)
            }
        }

        // --- ImageCapture
        val captureBuilder = ImageCapture.Builder()
            .setTargetAspectRatio(AspectRatio.RATIO_16_9)
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
        if (macroEnabled) {
            try {
                val ext = Camera2Interop.Extender(captureBuilder)
                ext.setCaptureRequestOption(
                    CaptureRequest.CONTROL_MODE,
                    CameraMetadata.CONTROL_MODE_USE_SCENE_MODE
                )
                ext.setCaptureRequestOption(
                    CaptureRequest.CONTROL_SCENE_MODE,
                    CameraMetadata.CONTROL_AF_MODE_MACRO
                )
                ext.setCaptureRequestOption(
                    CaptureRequest.CONTROL_AF_MODE,
                    CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
                )
            } catch (t: Throwable) {
                Log.w("CameraX", "Macro interop (Capture) not applied: ${t.message}")
            }
        }
        imageCapture = captureBuilder.build()

        // Rebind
        provider.unbindAll()
        try {
            camera = cameraSelector?.let {
                provider.bindToLifecycle(
                    lifecycleOwner,
                    it,
                    preview,
                    imageCapture,
                    imageAnalysis
                )
            }
        } catch (exc: Exception) {
            Log.e("CameraX", "Use case binding failed", exc)
            return
        }

        // Observe zoom changes -> send to Flutter
        camera?.cameraInfo?.zoomState?.observe(lifecycleOwner, Observer { state ->
            state?.let { methodChannel.invokeMethod("onZoomChanged", it.zoomRatio) }
        })

        // Optional small zoom nudge when macro is enabled (helps framing)
        if (macroEnabled) {
            val state = camera?.cameraInfo?.zoomState?.value
            val minZ = state?.minZoomRatio ?: 1f
            val maxZ = state?.maxZoomRatio ?: 1f
            val target = 1.3f.coerceIn(minZ, maxZ)
            camera?.cameraControl?.setZoomRatio(target)
        }

        // Send macro status
        methodChannel.invokeMethod("onMacroChanged", buildMacroStatus())
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun setupCamera() {
        val activity = getActivity(context)
        val lifecycleOwner = activity as LifecycleOwner

        val options = BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS)
            .build()
        barcodeScanner = BarcodeScanning.getClient(options)

        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            cameraProvider = cameraProviderFuture.get()

            // (Re)bind with current selector + macro settings
            bindUseCases(lifecycleOwner)
        }, ContextCompat.getMainExecutor(context))
    }

    private fun takePicture(result: MethodChannel.Result) {
        val file = File(context.cacheDir, "captured_image_${System.currentTimeMillis()}.jpg")
        val outputOptions = ImageCapture.OutputFileOptions.Builder(file).build()

        imageCapture?.takePicture(
            outputOptions,
            ContextCompat.getMainExecutor(context),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                    result.success(file.absolutePath)
                }

                override fun onError(exception: ImageCaptureException) {
                    result.error("IMAGE_CAPTURE_FAILED", "Failed to capture image", exception.message)
                }
            })
    }

    private fun getActivity(context: Context): Activity? {
        var contextTemp = context
        while (contextTemp is android.content.ContextWrapper) {
            if (contextTemp is Activity) return contextTemp
            contextTemp = contextTemp.baseContext
        }
        return null
    }

    // ===== Barcode analysis with simple ITF debouncing (your logic preserved) =====
    @OptIn(ExperimentalGetImage::class)
    @RequiresApi(Build.VERSION_CODES.N)
    private fun processImageProxy(imageProxy: ImageProxy) {
        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            val currentTime = System.currentTimeMillis()

            barcodeScanner.process(image)
                .addOnSuccessListener { barcodes ->
                    for (barcode in barcodes) {
                        val rawValue = barcode.rawValue ?: continue
                        val format = barcode.format

                        if (format == Barcode.FORMAT_ITF) {
                            val timestamps = barcodeTimestamps.getOrPut(rawValue) { mutableListOf() }
                            timestamps.add(currentTime)
                            timestamps.retainAll { currentTime - it <= detectionWindowMs }
                            if (timestamps.size >= detectionThreshold) {
                                methodChannel.invokeMethod("onBarcodeScanned", rawValue)
                                methodChannel.invokeMethod("onBarcodeDataScanned", Gson().toJson(BarcodeData(barcode)))
                                barcodeTimestamps.remove(rawValue)
                            }
                        } else {
                            methodChannel.invokeMethod("onBarcodeScanned", rawValue)
                            methodChannel.invokeMethod("onBarcodeDataScanned", Gson().toJson(BarcodeData(barcode)))
                        }
                    }
                    val now = System.currentTimeMillis()
                    barcodeTimestamps.entries.removeIf { (_, times) -> times.all { now - it > detectionWindowMs } }
                }
                .addOnFailureListener { Log.e("Barcode", "Failed to scan barcode", it) }
                .addOnCompleteListener { imageProxy.close() }
        } else {
            imageProxy.close()
        }
    }

    // ======= Zoom: pinch + double tap + programmatic =======
    private fun attachZoomGestures(view: PreviewView) {
        scaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
                lastGestureZoomRatio = camera?.cameraInfo?.zoomState?.value?.zoomRatio ?: 1f
                return true
            }

            override fun onScale(detector: ScaleGestureDetector): Boolean {
                val state = camera?.cameraInfo?.zoomState?.value ?: return false
                val minZ = state.minZoomRatio
                val maxZ = state.maxZoomRatio
                val newZoom = (lastGestureZoomRatio * detector.scaleFactor).coerceIn(minZ, maxZ)
                camera?.cameraControl?.setZoomRatio(newZoom)
                return true
            }
        })

        gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDoubleTap(e: MotionEvent): Boolean {
                resetZoom()
                return true
            }
        })

        view.setOnTouchListener { _, ev ->
            var handled = false
            scaleDetector?.let { handled = it.onTouchEvent(ev) || handled }
            gestureDetector?.let { handled = it.onTouchEvent(ev) || handled }
            handled
        }
    }

    private fun attachPinchToZoom() {
        scaleDetector = android.view.ScaleGestureDetector(
            context,
            object : android.view.ScaleGestureDetector.SimpleOnScaleGestureListener() {

                override fun onScaleBegin(detector: android.view.ScaleGestureDetector): Boolean {
                    // cache current ratio at gesture start
                    pinchZoomRatio = camera?.cameraInfo?.zoomState?.value?.zoomRatio ?: 1f
                    return true
                }

                override fun onScale(detector: android.view.ScaleGestureDetector): Boolean {
                    val st = camera?.cameraInfo?.zoomState?.value ?: return false
                    val minZ = st.minZoomRatio
                    val maxZ = st.maxZoomRatio

                    // ACCUMULATE: multiply the running ratio by the *incremental* factor
                    // (Android's scaleFactor is per-event, not cumulative)
                    // Optional sensitivity boost: raise factor to a power (>1 = faster)
                    val factor = Math.pow(detector.scaleFactor.toDouble(), 1.25).toFloat()

                    pinchZoomRatio = (pinchZoomRatio * factor).coerceIn(minZ, maxZ)
                    camera?.cameraControl?.setZoomRatio(pinchZoomRatio)
                    return true
                }

                override fun onScaleEnd(detector: android.view.ScaleGestureDetector) {
                    // keep the final ratio as the new baseline
                    pinchZoomRatio = camera?.cameraInfo?.zoomState?.value?.zoomRatio ?: pinchZoomRatio
                }
            }
        )

        // Attach to your outer container so it always receives multitouch
        linearLayout.isClickable = true
        linearLayout.isFocusable = true
        linearLayout.isFocusableInTouchMode = true
        linearLayout.setOnTouchListener { v, ev ->
            v.parent?.requestDisallowInterceptTouchEvent(true)
            scaleDetector?.onTouchEvent(ev)
            true
        }
    }


    private fun attachDoubleTapReset() {
        tapDetector = android.view.GestureDetector(
            context,
            object : android.view.GestureDetector.SimpleOnGestureListener() {
                override fun onDoubleTap(e: android.view.MotionEvent): Boolean {
                    // Reset to 1.0x (ratio) — same idea as iOS double-tap
                    val st = camera?.cameraInfo?.zoomState?.value ?: return true
                    val minZ = st.minZoomRatio
                    val maxZ = st.maxZoomRatio
                    camera?.cameraControl?.setZoomRatio(1f.coerceIn(minZ, maxZ))
                    return true
                }
            }
        )

        // Feed both detectors (pinch + double-tap) and consume events
        linearLayout.setOnTouchListener { v, ev ->
            v.parent?.requestDisallowInterceptTouchEvent(true)
            var handled = false
            handled = (scaleDetector?.onTouchEvent(ev) == true) || handled
            handled = (tapDetector?.onTouchEvent(ev) == true) || handled
            true
        }

        // optional redundancy on the PreviewView
        previewView.setOnTouchListener { v, ev ->
            v.parent?.requestDisallowInterceptTouchEvent(true)
            var handled = false
            handled = (scaleDetector?.onTouchEvent(ev) == true) || handled
            handled = (tapDetector?.onTouchEvent(ev) == true) || handled
            true
        }
    }

    private fun setZoom(ratio: Float) {
        val state = camera?.cameraInfo?.zoomState?.value ?: return
        val minZ = state.minZoomRatio
        val maxZ = state.maxZoomRatio
        camera?.cameraControl?.setZoomRatio(ratio.coerceIn(minZ, maxZ))
    }

    private fun resetZoom() {
        setZoom(1f)
    }

    // ======= Macro toggle (best-effort via Camera2 SCENE_MODE_MACRO) =======
    @RequiresApi(Build.VERSION_CODES.N)
    private fun setMacro(enabled: Boolean) {
        macroEnabled = enabled
        val lifecycleOwner = getActivity(context) as? LifecycleOwner ?: return
        // Rebind with new interop flags
        bindUseCases(lifecycleOwner)
    }

    // Build a status map similar to iOS for debugging/visibility
    @OptIn(ExperimentalCamera2Interop::class)
    private fun buildMacroStatus(): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>(
            "requestedMacro" to macroEnabled
        )
        val cam = camera ?: return map
        val info2 = try { Camera2CameraInfo.from(cam.cameraInfo) } catch (_: Throwable) { null }

        map["zoomRatio"] = cam.cameraInfo.zoomState.value?.zoomRatio
        map["maxZoomRatio"] = cam.cameraInfo.zoomState.value?.maxZoomRatio
        map["minZoomRatio"] = cam.cameraInfo.zoomState.value?.minZoomRatio

//        info2?.let { c2 ->
//            try {
//                val chars = c2.cameraCharacteristics
//                val facing = chars.get(CameraCharacteristics.LENS_FACING)
//                map["lensFacing"] = when (facing) {
//                    CameraCharacteristics.LENS_FACING_FRONT -> "front"
//                    CameraCharacteristics.LENS_FACING_BACK -> "back"
//                    CameraCharacteristics.LENS_FACING_EXTERNAL -> "external"
//                    else -> "unknown"
//                }
//                val minFocus = chars.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE)
//                map["minFocusDistanceDiopters"] = minFocus
//                val focals = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
//                map["focalLengths"] = focals?.map { it.toDouble() }
//
//                val modes = chars.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES) ?: intArrayOf()
//                map["supportsMacroAfMode"] = modes.contains(CaptureRequest.CONTROL_AF_MODE_MACRO)
//            } catch (t: Throwable) {
//                map["cameraInfoError"] = t.message
//            }
//        }
        return map
    }

    override fun getView(): FrameLayout = linearLayout

    override fun dispose() {
        cameraExecutor.shutdown()
    }

    @RequiresApi(Build.VERSION_CODES.N)
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android" + Build.VERSION.RELEASE)

            "changeFlashMode" -> {
                val flashModeID = call.argument<Int>("flashModeID")!!
                changeFlashMode(flashModeID, result)
                result.success(true)
            }

            "switchCamera" -> {
                val cameraID = call.argument<Int>("cameraID")!!
                switchCamera(cameraID, result)
                result.success(true)
            }

            "pauseCamera" -> {
                pauseCamera(result)
                result.success(true)
            }

            "resumeCamera" -> {
                resumeCamera(result)
                result.success(true)
            }

            "takePicture" -> takePicture(result)

            // === New: Zoom API parity with iOS ===
            "setZoom" -> {
                val z = call.argument<Double>("zoom")
                if (z != null) {
                    setZoom(z.toFloat())
                    result.success(true)
                } else {
                    result.error("bad_args", "zoom (Double) required", null)
                }
            }
            "resetZoom" -> {
                resetZoom()
                result.success(true)
            }

            // === New: Macro toggle parity with iOS ===
            "setMacro" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                setMacro(enabled)
                result.success(true)
            }

            "dispose" -> dispose()
            else -> result.notImplemented()
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun switchCamera(cameraID: Int, result: MethodChannel.Result) {
        cameraSelector = if (cameraID == 0) {
            CameraSelector.DEFAULT_BACK_CAMERA
        } else {
            CameraSelector.DEFAULT_FRONT_CAMERA
        }
        setupCamera()
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun resumeCamera(result: MethodChannel.Result) {
        setupCameraSelector()
        setupCamera()
    }

    private fun pauseCamera(result: MethodChannel.Result) {
        cameraProvider?.unbindAll()
        try { barcodeScanner.close() } catch (_: Throwable) {}
    }

    private fun getFlashMode(flashModeID: Int): Int {
        return when (flashModeID) {
            1 -> ImageCapture.FLASH_MODE_ON
            0 -> ImageCapture.FLASH_MODE_OFF
            else -> ImageCapture.FLASH_MODE_AUTO
        }
    }

    private fun changeFlashMode(flashModeID: Int, result: MethodChannel.Result) {
        camera?.cameraControl?.enableTorch(flashModeID == 1)
    }
}
