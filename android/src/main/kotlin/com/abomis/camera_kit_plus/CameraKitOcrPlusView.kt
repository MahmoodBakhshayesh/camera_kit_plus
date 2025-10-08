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
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.annotation.OptIn
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
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
import androidx.lifecycle.Observer
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
import io.flutter.plugin.platform.PlatformView
import java.util.Objects
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

//import kotlin.math.coerceIn

class CameraKitOcrPlusView(context: Context, messenger: BinaryMessenger) :
    FrameLayout(context), PlatformView, MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, "camera_kit_plus")
    private lateinit var previewView: PreviewView
    private lateinit var linearLayout: FrameLayout
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private lateinit var textScanner: TextRecognizer
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var cameraSelector: CameraSelector? = null

    private var preview: Preview? = null
    private var analysis: ImageAnalysis? = null
    private var imageCapture: ImageCapture? = null // torch helper parity
    val REQUEST_CAMERA_PERMISSION = 1001

    // ===== Zoom / gestures =====
//    private var scaleDetector: android.view.ScaleGestureDetector? = null
//    private var gestureDetector: GestureDetector? = null
//    private var lastGestureZoomRatio: Float = 1f

    private var scaleDetector: android.view.ScaleGestureDetector? = null
    private var gestureDetector: android.view.GestureDetector? = null
    private var pinchActive = false
    private var pinchStartLinearZoom = 0f
    private var tapDetector: android.view.GestureDetector? = null

    //    private var scaleDetector: android.view.ScaleGestureDetector? = null
    private var lastZoomRatioFromBegan: Float = 1f
    private var pinchZoomRatio: Float = 1f

    // Helper to read/write linear zoom safely
    private fun getLinearZoom(): Float =
        camera?.cameraInfo?.zoomState?.value?.let { it.linearZoom } ?: 0f

    private fun setLinearZoomSafe(v: Float) {
        camera?.cameraControl?.setLinearZoom(v.coerceIn(0f, 1f))
    }

    // Optional helpers if you still want ratio-based APIs elsewhere
    private fun getZoomRatio(): Float =
        camera?.cameraInfo?.zoomState?.value?.zoomRatio ?: 1f

    private fun setZoomRatioSafe(v: Float) {
        val st = camera?.cameraInfo?.zoomState?.value ?: return
        camera?.cameraControl?.setZoomRatio(v.coerceIn(st.minZoomRatio, st.maxZoomRatio))
    }


    // ===== Macro bias toggle =====
    private var macroEnabled: Boolean = false

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


        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
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

    private fun setupCamera() {
        val activity = getActivity(context)
        val lifecycleOwner = activity as LifecycleOwner

        textScanner = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            cameraProvider = cameraProviderFuture.get()
            bindUseCases(lifecycleOwner)
        }, ContextCompat.getMainExecutor(context))
    }

    @OptIn(ExperimentalCamera2Interop::class)
    private fun bindUseCases(lifecycleOwner: LifecycleOwner) {
        val provider = cameraProvider ?: return

        // --- Preview (with optional MACRO scene mode)
        val previewBuilder = Preview.Builder()
            .setTargetAspectRatio(AspectRatio.RATIO_16_9)

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

        // --- Analysis (OCR)
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

        analysis = analysisBuilder.build().also { a ->
            a.setAnalyzer(cameraExecutor) { imageProxy -> processImageProxy(imageProxy) }
        }

        // --- ImageCapture (for torch parity & future stills)
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

        provider.unbindAll()
        try {
            camera = cameraSelector?.let {
                provider.bindToLifecycle(
                    lifecycleOwner,
                    it,
                    preview,
                    analysis,
                    imageCapture
                )
            }
        } catch (exc: Exception) {
            Log.e("CameraX", "Use case binding failed", exc)
            return
        }

        // Send zoom changes up to Flutter
        camera?.cameraInfo?.zoomState?.observe(lifecycleOwner, Observer { state ->
            state?.let { methodChannel.invokeMethod("onZoomChanged", it.zoomRatio) }
        })

        // Small zoom nudge for macro (helps near focus framing)
        if (macroEnabled) {
            val st = camera?.cameraInfo?.zoomState?.value
            val minZ = st?.minZoomRatio ?: 1f
            val maxZ = st?.maxZoomRatio ?: 1f
            camera?.cameraControl?.setZoomRatio(1.3f.coerceIn(minZ, maxZ))
        }

        // Report macro status
        methodChannel.invokeMethod("onMacroChanged", buildMacroStatus())
    }

    private fun getActivity(context: Context): Activity? {
        var contextTemp = context
        while (contextTemp is android.content.ContextWrapper) {
            if (contextTemp is Activity) return contextTemp
            contextTemp = contextTemp.baseContext
        }
        return null
    }

    // ===== OCR frame processing =====
    @OptIn(ExperimentalGetImage::class)
    private fun processImageProxy(imageProxy: ImageProxy) {
        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val image =
                InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            textScanner.process(image)
                .addOnSuccessListener { text ->
                    val content = text.text.trim()
                    if (content.isNotEmpty()) {
                        val lineModels: MutableList<LineModel> = ArrayList()
                        for (b in text.textBlocks) {
                            for (line in b.lines) {
                                val lineModel = LineModel(line.text)
                                val cps = line.cornerPoints
                                if (cps != null) {
                                    for (p in cps) {
                                        lineModel.cornerPoints.add(
                                            CornerPointModel(p.x.toFloat(), p.y.toFloat())
                                        )
                                    }
                                }
                                lineModels.add(lineModel)
                            }
                        }
                        Log.println(Log.ERROR, "", "scanned");
                        val map: MutableMap<String, Any> = HashMap()
                        map["text"] = content
                        map["lines"] = lineModels
                        map["path"] = ""
                        map["orientation"] = 0
                        methodChannel.invokeMethod("onTextRead", Gson().toJson(map))
                    }
                }
                .addOnFailureListener { Log.e("Text", "Failed to recognize text", it) }
                .addOnCompleteListener { imageProxy.close() }
        } else {
            imageProxy.close()
        }
    }

    // ===== Gestures: pinch zoom + double-tap reset =====
    // New gesture impl
    private fun attachZoomGestures(view: PreviewView) {
        val scaleListener = object : android.view.ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScaleBegin(detector: android.view.ScaleGestureDetector): Boolean {
                pinchActive = true
                pinchStartLinearZoom = getLinearZoom()
                return true
            }

            override fun onScale(detector: android.view.ScaleGestureDetector): Boolean {
                // Convert pinch scale (around 1.0) into a tiny linear delta
                val scale = detector.scaleFactor
                // Dead-zone: ignore micro jitters within ±2%
                if (kotlin.math.abs(scale - 1f) < 0.02f) return true

                // Sensitivity: tune 0.15f..0.30f; larger = faster zoom
                val sensitivity = 0.22f
                val delta = (scale - 1f) * sensitivity

                setLinearZoomSafe(pinchStartLinearZoom + delta)
                return true
            }

            override fun onScaleEnd(detector: android.view.ScaleGestureDetector) {
                // Lock in the new baseline for the next pinch
                pinchStartLinearZoom = getLinearZoom()
                pinchActive = false
            }
        }

        scaleDetector = android.view.ScaleGestureDetector(context, scaleListener)

        gestureDetector = android.view.GestureDetector(
            context,
            object : android.view.GestureDetector.SimpleOnGestureListener() {
                override fun onDoubleTap(e: android.view.MotionEvent): Boolean {
                    // Double-tap -> reset to 1.0x
                    setLinearZoomSafe(0f)
                    return true
                }
            }
        )

        view.setOnTouchListener { _, ev ->
            var handled = false
            scaleDetector?.let { handled = it.onTouchEvent(ev) || handled }
            gestureDetector?.let { handled = it.onTouchEvent(ev) || handled }
            handled
        }
    }


    private fun setZoom(ratio: Float) {
        val st = camera?.cameraInfo?.zoomState?.value ?: return
        val minZ = st.minZoomRatio
        val maxZ = st.maxZoomRatio
        camera?.cameraControl?.setZoomRatio(ratio.coerceIn(minZ, maxZ))
    }

    private fun resetZoom() {
        setZoom(1f)
    }

    // ===== Macro toggle (best-effort via SCENE_MODE_MACRO) =====
    private fun setMacro(enabled: Boolean) {
        macroEnabled = enabled
        val lifecycleOwner = getActivity(context) as? LifecycleOwner ?: return
        bindUseCases(lifecycleOwner)
    }

    private fun buildMacroStatus(): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>(
            "requestedMacro" to macroEnabled
        )
        val cam = camera ?: return map
//        val info2 = try { Camera2CameraInfo.from(cam.cameraInfo) } catch (_: Throwable) { null }

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



    private fun switchCamera(cameraID: Int, result: MethodChannel.Result) {
        cameraSelector = if (cameraID == 0) {
            CameraSelector.DEFAULT_BACK_CAMERA
        } else {
            CameraSelector.DEFAULT_FRONT_CAMERA
        }
        setupCamera()
    }

    private fun resumeCamera(result: MethodChannel.Result) {
        setupCameraSelector()
        setupCamera()
    }

    private fun pauseCamera(result: MethodChannel.Result) {
        cameraProvider?.unbindAll()
        try {
            textScanner.close()
        } catch (_: Throwable) {
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
        camera?.cameraControl?.enableTorch(flashModeID == 1)
    }
}
