package com.abomis.camera_kit_plus

import android.Manifest
import android.app.Activity
import android.content.ContentValues.TAG
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.Point
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.params.StreamConfigurationMap
import android.media.ImageReader
import android.opengl.GLES20
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.DisplayMetrics
import android.util.Log
import android.util.SparseIntArray
import android.view.Surface
import android.view.TextureView
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.annotation.RequiresApi
import androidx.camera.core.AspectRatio
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
import com.abomis.camera_kit_plus.Classes.AutoFitTextureView
import com.abomis.camera_kit_plus.Classes.BarcodeData
import com.abomis.camera_kit_plus.Classes.BarcodeDetector
import com.abomis.camera_kit_plus.Classes.CameraConstants
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
import java.util.Arrays
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit


class CameraView2(context: Context, messenger: BinaryMessenger) : FrameLayout(context), PlatformView, MethodCallHandler {
    private val methodChannel = MethodChannel(messenger, "camera_kit_plus")
    private lateinit var previewView: PreviewView
    private lateinit var linearLayout: FrameLayout
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var imageCapture: ImageCapture? = null

    private lateinit var barcodeScanner: BarcodeScanner
    private var cameraProvider: ProcessCameraProvider? = null

    private var preview: Preview? = null
    val REQUEST_CAMERA_PERMISSION = 1001

    private var mCameraDevice: CameraDevice? = null
    private var mPreviewSession: CameraCaptureSession? = null
    private var mBackgroundThread: HandlerThread? = null
    private val mCameraOpenCloseLock: Semaphore = Semaphore(1)
    private var mCameraId: String? = null
    private var mFacingSupported = true
    private var mCameraCharacteristics: CameraCharacteristics? = null
    private val mFacing: Int = CameraConstants.FACING_BACK
    private val mBackgroundHandler: Handler? = null
    private val mAutoFocusSupported = false
    private val mFlashSupported = false
    private val INTERNAL_FACINGS: SparseIntArray = SparseIntArray()
    private var mImageReader: ImageReader? = null
    private var mPreviewRequestBuilder: CaptureRequest.Builder? = null
    private val mAutoFocus = true
    private var mPreviewRequest: CaptureRequest? = null
    private var textureView: AutoFitTextureView? = null


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

        textureView = AutoFitTextureView(getActivity(context))
        textureView!!.layoutParams = LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )

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
        textureView = AutoFitTextureView(getActivity(context))
        textureView!!.layoutParams = LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        displaymetrics = context.resources.displayMetrics
        val screenWidth = displaymetrics.widthPixels
        val screenHeight = displaymetrics.heightPixels
        displaySize.x = screenWidth
        displaySize.y = screenHeight
        linearLayout.layoutParams = LayoutParams(displaySize.x, displaySize.y)
        linearLayout.addView(previewView)

        textureView!!.layoutParams = LayoutParams(displaySize.x, displaySize.y);
        setupCameraSelector()
        setupCamera()
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        previewView.layout(0, 0, right - left, bottom - top)
    }


    private  fun setupCameraSelector(){
//        cameraSelector =  CameraSelector.DEFAULT_BACK_CAMERA
//        setupCameraOutputs()
    }

    private fun createCameraPreviewSession() {
        try {
            Log.println(Log.ERROR,(textureView == null).toString(),"is textureView null")
//            val texture: SurfaceTexture = checkNotNull(textureView!!.getSurfaceTexture())

            val textureId = IntArray(1)
            GLES20.glGenTextures(1, textureId, 0)

            val surfaceTexture = SurfaceTexture(textureId[0])
            val surface = Surface(surfaceTexture)
//            val texture = SurfaceTexture(0)
            // We configure the size of default buffer to be the size of camera preview we want.
//            texture.setDefaultBufferSize(1080, 1920)
            // This is the output Surface we need to start preview.
//            val surface: Surface = Surface(texture)


            // We set up a CaptureRequest.Builder with the output Surface.
            mPreviewRequestBuilder = mCameraDevice!!.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            mPreviewRequestBuilder!!.addTarget(surface)
            mPreviewRequestBuilder!!.addTarget(mImageReader!!.surface)

            // Here, we create a CameraCaptureSession for camera preview.
            mCameraDevice!!.createCaptureSession(
                Arrays.asList<Surface>(surface, mImageReader!!.surface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(cameraCaptureSession: CameraCaptureSession) {
                        // The camera is already closed
                        if (null == mCameraDevice) {
                            return
                        }

                        // When the session is ready, we start displaying the preview.
                        mPreviewSession = cameraCaptureSession
                        try {
                            // Auto focus should be continuous for camera preview.
//                            mPreviewRequestBuilder.set(CaptureRequest.CONTROL_AF_MODE,
//                                CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
//                            updateAutoFocus()
                            // Flash is automatically enabled when necessary.
//                            updateFlash(mPreviewRequestBuilder)

                            // Finally, we start displaying the camera preview.
                            mPreviewRequest = mPreviewRequestBuilder!!.build()
                            mPreviewSession!!.setRepeatingRequest(
                                mPreviewRequest!!,
                                mCaptureCallback, mBackgroundHandler
                            )
                        } catch (e: CameraAccessException) {
                            e.printStackTrace()
                        }
                    }

                    override fun onConfigureFailed(
                        cameraCaptureSession: CameraCaptureSession
                    ) {
//                            showToast("Create preview configure failed");
                    }
                }, mBackgroundHandler
            )
        } catch (e: CameraAccessException) {
            e.printStackTrace()
        }
    }

    private val mCaptureCallback
            : CameraCaptureSession.CaptureCallback = object : CameraCaptureSession.CaptureCallback() {
        private fun process(result: CaptureResult) {
            //  Log.i(TAG, "CaptureCallback mState: " + mState);
//            when (mState) {
//                STATE_PREVIEW -> {}
//                STATE_WAITING_LOCK -> {
//                    val afState = result.get(CaptureResult.CONTROL_AF_STATE)
//                    Log.i(TAG, "STATE_WAITING_LOCK afState: $afState")
//                    if (afState == null) {
//                        mState = STATE_PICTURE_TAKEN
//                        captureStillPicture()
//                    } else if (CaptureResult.CONTROL_AF_STATE_FOCUSED_LOCKED == afState ||
//                        CaptureResult.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED == afState
//                    ) {
//                        // CONTROL_AE_STATE can be null on some devices
//                        val aeState = result.get(CaptureResult.CONTROL_AE_STATE)
//                        if (aeState == null ||
//                            aeState == CaptureResult.CONTROL_AE_STATE_CONVERGED
//                        ) {
//                            mState = STATE_PICTURE_TAKEN
//                            captureStillPicture()
//                        } else {
//                            runPrecaptureSequence()
//                        }
//                    }
//                }
//
//                STATE_WAITING_PRECAPTURE -> {
//                    // CONTROL_AE_STATE can be null on some devices
//                    val aeState = result.get(CaptureResult.CONTROL_AE_STATE)
//                    if (aeState == null || aeState == CaptureResult.CONTROL_AE_STATE_PRECAPTURE || aeState == CaptureRequest.CONTROL_AE_STATE_FLASH_REQUIRED) {
//                        mState = STATE_WAITING_NON_PRECAPTURE
//                    }
//                }
//
//                STATE_WAITING_NON_PRECAPTURE -> {
//                    // CONTROL_AE_STATE can be null on some devices
//                    val aeState = result.get(CaptureResult.CONTROL_AE_STATE)
//                    if (aeState == null || aeState != CaptureResult.CONTROL_AE_STATE_PRECAPTURE) {
//                        mState = STATE_PICTURE_TAKEN
//                        captureStillPicture()
//                    }
//                }
//            }
        }

        override fun onCaptureProgressed(
            session: CameraCaptureSession,
            request: CaptureRequest,
            partialResult: CaptureResult
        ) {
            process(partialResult)
        }

        override fun onCaptureCompleted(
            session: CameraCaptureSession,
            request: CaptureRequest,
            result: TotalCaptureResult
        ) {
            if (true) {
//                if (previewFlashMode === 'A') {
//                    val aeState = result.get(CaptureResult.CONTROL_AE_STATE)
//                    if (aeState != null) {
//                        if (aeState == CaptureResult.CONTROL_AE_STATE_FLASH_REQUIRED) {
//                            changeFlashMode('O')
//                            //                            updateFlash(mPreviewRequestBuilder);
//                        }
//                    }
//                }
            } else {
                process(result)
            }
        }
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



            textureView = AutoFitTextureView(activity)
            textureView!!.layoutParams = LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            // Select the back camera as default
//            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            // Unbind all use cases before rebinding
            cameraProvider?.unbindAll()
            preview = Preview.Builder().setTargetAspectRatio(AspectRatio.RATIO_16_9).setTargetRotation(previewView.rotation.toInt()).build()


            preview!!.setSurfaceProvider(previewView.surfaceProvider)

            try {
                setupCameraOutputs()
                val manager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
                try {
                    if (!mCameraOpenCloseLock.tryAcquire(CameraConstants.OPEN_CAMERA_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                        throw RuntimeException("Time out waiting to lock camera opening.")
                    }
                    //            mMediaRecorder = new MediaRecorder();
                    manager.openCamera(mCameraId!!, mStateCallback, mBackgroundHandler)
                } catch (e: CameraAccessException) {
                    e.printStackTrace()
                } catch (e: InterruptedException) {
                    throw RuntimeException("Interrupted while trying to lock camera opening.", e)
                }
//                camera = cameraProvider?.bindToLifecycle(
//                    lifecycleOwner,
//                    cameraSelector!!,
//                    preview,
//                    imageCapture,
//                    imageAnalysis
//                )
            } catch (exc: Exception) {
                Log.e("Camera2", "Use case binding failed", exc)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private val mStateCallback: CameraDevice.StateCallback = object : CameraDevice.StateCallback() {
        override fun onOpened(cameraDevice: CameraDevice) {
            // This method is called when the camera is opened.  We start camera preview here.
            mCameraOpenCloseLock.release()
            mCameraDevice = cameraDevice
            createCameraPreviewSession()
        }

        override fun onDisconnected(cameraDevice: CameraDevice) {
            mCameraOpenCloseLock.release()
            cameraDevice.close()
            mCameraDevice = null
        }

        override fun onError(cameraDevice: CameraDevice, error: Int) {
            mCameraOpenCloseLock.release()
            cameraDevice.close()
            mCameraDevice = null
        }
    }


    @RequiresApi(api = Build.VERSION_CODES.LOLLIPOP)
    private fun setupCameraOutputs() {
        val activity = getActivity(context)
        val internalFacing: Int = INTERNAL_FACINGS.get(mFacing)
        val manager = activity!!.getSystemService(Context.CAMERA_SERVICE) as CameraManager

        try {
            val cameraIds = manager.cameraIdList
            mFacingSupported = cameraIds.size > 1
            for (cameraId in cameraIds) {
                mCameraCharacteristics = manager.getCameraCharacteristics(cameraId)

                val facing: Int? = mCameraCharacteristics!!.get(CameraCharacteristics.LENS_FACING)
                if (facing == null || facing != internalFacing) {
                    continue
                }

                val map: StreamConfigurationMap? = mCameraCharacteristics!!.get(
                    CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP
                )
                if (map == null) {
                    continue
                }



//                // For still image captures, we use the largest available size.
//                if (hasBarcodeReader) {
                    mImageReader = ImageReader.newInstance(
                        1080, 1920,
                        ImageFormat.YUV_420_888, 2
                    )
                    BarcodeDetector.setImageReader(mImageReader)
//                }
                mCameraId = cameraId
                Log.i(TAG, "CameraId: $mCameraId ,isFlashSupported: $mFlashSupported")
//                createCameraPreviewSession()
                return
            }
        } catch (e: CameraAccessException) {
            e.printStackTrace()
        } catch (e: NullPointerException) {
            e.printStackTrace()
        }
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
//        if(cameraID == 0){
//            cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
//            setupCamera()
//
//        }else{
//            cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA
//            setupCamera()
//
//        }
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
//        if (camera != null) {
//            camera!!.getCameraControl().enableTorch(flashModeID == 1)
//        }
    }
}
