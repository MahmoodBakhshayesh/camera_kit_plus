import android.Manifest
import android.annotation.SuppressLint
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
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.media.Image
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Message
import android.util.Log
import android.util.Size
import android.view.Surface
import android.view.TextureView
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.abomis.camera_kit_plus.Classes.BarcodeDetector
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
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.Arrays
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore


@SuppressLint("ViewConstructor")
class CameraView2(context: Context, messenger: BinaryMessenger) : FrameLayout(context), PlatformView,
    MethodChannel.MethodCallHandler {


    private  val STATE_PREVIEW: Int = 0

    /**
     * Camera state: Waiting for the focus to be locked.
     */
    private val STATE_WAITING_LOCK: Int = 1

    /**
     * Camera state: Waiting for the exposure to be precapture state.
     */
    private val STATE_WAITING_PRECAPTURE: Int = 2

    /**
     * Camera state: Waiting for the exposure state to be something other than precapture.
     */
    private  val STATE_WAITING_NON_PRECAPTURE: Int = 3

    /**
     * Camera state: Picture was taken.
     */
    private val STATE_PICTURE_TAKEN: Int = 4

    private val MSG_CAPTURE_PICTURE_WHEN_FOCUS_TIMEOUT: Int = 100


    private val methodChannel = MethodChannel(messenger, "camera_kit_plus")
    private var linearLayout: FrameLayout
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private lateinit var barcodeScanner: BarcodeScanner

    private lateinit var cameraManager: CameraManager
    private var mCameraDevice: CameraDevice? = null
//    private var captureSession: CameraCaptureSession? = null
    private var previewSurface: Surface? = null

    private var textureView: TextureView
    private var flashMode: Boolean = false // Track the current flash mode (ON/OFF)
    private var isCameraPaused = false // Track the state of camera (paused or not)
    val REQUEST_CAMERA_PERMISSION = 1001

    private var options: BarcodeScannerOptions? = null
    private var mBackgroundThread: HandlerThread? = null
    private var mBackgroundHandler: Handler? = null
    private var mImageReader: ImageReader? = null
    private var mState = STATE_PREVIEW
    private val mCameraOpenCloseLock: Semaphore = Semaphore(1)

    private var mPreviewRequest: CaptureRequest? = null
    private var mPreviewRequestBuilder: CaptureRequest.Builder? = null
    private var mPreviewSession: CameraCaptureSession? = null
    private var isProcessingImage = false

    private var mOnImageAvailableListener = ImageReader.OnImageAvailableListener { reader ->

        val image = reader.acquireLatestImage()
        BarcodeDetector.detectImage(mImageReader, barcodeScanner, image, methodChannel, 0)
//        val image = reader.acquireLatestImage()
//        if(image!=null) {
//            if (isProcessingImage) {
//                image.close();
//            } else {
//                val image = reader.acquireLatestImage()
//                isProcessingImage = true
//                BarcodeDetector.detectImage(mImageReader, barcodeScanner, image, methodChannel, 0)
//                isProcessingImage = false
//            }
//        }

    }


    init {
        // Initialize the layout for the camera preview
        linearLayout = getActivity(context)?.let { FrameLayout(it) }!!
        linearLayout.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.MATCH_PARENT
        )
        linearLayout.setBackgroundColor(Color.parseColor("#FFFFFF"))
        textureView = getActivity(context)?.let { TextureView(it) }!!
        textureView.layoutParams = LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        linearLayout.addView(textureView)


        // Set scale type for maintaining aspect ratio
        textureView.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
                setupPreview()
            }

            override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
                adjustPreviewAspectRatio()
            }

            override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean = false

            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}
        }

        methodChannel.setMethodCallHandler(this)
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                getActivity(context)!!,
                arrayOf(Manifest.permission.CAMERA),
                REQUEST_CAMERA_PERMISSION
            )
        } else {

        }
    }

    private fun setupPreview() {
        // Get the screen size
        val displaySize = Point()
        val displayMetrics = context.resources.displayMetrics
        val screenWidth = displayMetrics.widthPixels
        val screenHeight = displayMetrics.heightPixels
        displaySize.x = screenWidth
        displaySize.y = screenHeight
        linearLayout.layoutParams = LayoutParams(displaySize.x, displaySize.y)

        // Set up the camera preview
        cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = cameraManager.cameraIdList[0] // Default to back camera


        setupCamera(cameraId)
    }

    private fun setupCamera(cameraId: String) {
        // Get the preview size from the camera's characteristics (optional)
        val characteristics = cameraManager.getCameraCharacteristics(cameraId)
        val streamConfigurationMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val sizes = streamConfigurationMap?.getOutputSizes(SurfaceTexture::class.java)
        val previewSize = sizes?.firstOrNull() ?: sizes?.lastOrNull()

        // Calculate the aspect ratio
        val cameraAspectRatio = previewSize?.let { it.height.toFloat() / it.width.toFloat() }
        val displayMetrics = context.resources.displayMetrics
        val screenAspectRatio = displayMetrics.heightPixels.toFloat() / displayMetrics.widthPixels.toFloat()

        // Adjust the size of TextureView to maintain the aspect ratio (crop if necessary)
        val layoutParams = textureView.layoutParams
        if (cameraAspectRatio != null) {
            if (cameraAspectRatio > screenAspectRatio) {
                // If the camera preview is wider than the screen, set the width to match the screen width
                val height = (displayMetrics.widthPixels / cameraAspectRatio).toInt()
                layoutParams.width = displayMetrics.widthPixels
                layoutParams.height = height
                val paddingTopBottom = (displayMetrics.heightPixels - height) / 2
                textureView.setPadding(
                    0,
                    paddingTopBottom,
                    0,
                    paddingTopBottom
                )  // Crop top and bottom
            } else {
                // If the camera preview is taller than the screen, set the height to match the screen height
                val width = (displayMetrics.heightPixels * cameraAspectRatio).toInt()
                layoutParams.height = displayMetrics.heightPixels
                layoutParams.width = width
                val paddingLeftRight = (displayMetrics.widthPixels - width) / 2
                textureView.setPadding(
                    paddingLeftRight,
                    0,
                    paddingLeftRight,
                    0
                )  // Crop left and right
            }
        }

        textureView.layoutParams = layoutParams

        // Now start the camera preview
        cameraManager.openCamera(cameraId, mStateCallback, mBackgroundHandler)
    }

    private val mStateCallback: CameraDevice.StateCallback = object : CameraDevice.StateCallback() {
        override fun onOpened(cd: CameraDevice) {
            // This method is called when the camera is opened.  We start camera preview here.
            mCameraOpenCloseLock.release()
            mCameraDevice = cd
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
            if (null != getActivity(context)) {
//                showToast("Camera is error: " + error);
//                activity.finish();
            }
        }
    }

    private fun createCameraPreviewSession() {
        try {
            setupPreviewSurface()
            startPreview()
            initializeImageCapture()
//            val texture = checkNotNull(textureView.surfaceTexture)
//             We configure the size of default buffer to be the size of camera preview we want.
//            texture.setDefaultBufferSize(mPreviewSize.getWidth(), mPreviewSize.getHeight())
//
//             This is the output Surface we need to start preview.
//            val surface = Surface(texture)

            // We set up a CaptureRequest.Builder with the output Surface.
//            mPreviewRequestBuilder = mCameraDevice!!.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
//            mPreviewRequestBuilder!!.addTarget(previewSurface!!)
//            mPreviewRequestBuilder!!.addTarget(mImageReader!!.surface)

            // Here, we create a CameraCaptureSession for camera preview.
//            mCameraDevice!!.createCaptureSession(
//                Arrays.asList<Surface>(previewSurface, mImageReader!!.surface),
//                object : CameraCaptureSession.StateCallback() {
//                    override fun onConfigured(cameraCaptureSession: CameraCaptureSession) {
//                        // The camera is already closed
//                        if (null == mCameraDevice) {
//                            return
//                        }
//
//                        // When the session is ready, we start displaying the preview.
//                        mPreviewSession = cameraCaptureSession
//                        try {
//                            // Auto focus should be continuous for camera preview.
////                            mPreviewRequestBuilder.set(CaptureRequest.CONTROL_AF_MODE,
////                                CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
////                            updateAutoFocus()
//                            // Flash is automatically enabled when necessary.
////                            updateFlash(mPreviewRequestBuilder)
//
//                            // Finally, we start displaying the camera preview.
//                            mPreviewRequest = mPreviewRequestBuilder!!.build()
//                            mPreviewSession!!.setRepeatingRequest(
//                                mPreviewRequest!!,
//                                mCaptureCallback, mBackgroundHandler
//                            )
//                        } catch (e: CameraAccessException) {
//                            e.printStackTrace()
//                        }
//                    }
//
//                    override fun onConfigureFailed(
//                        cameraCaptureSession: CameraCaptureSession
//                    ) {
////                            showToast("Create preview configure failed");
//                    }
//                }, mBackgroundHandler
//            )
        } catch (e: CameraAccessException) {
            e.printStackTrace()
        }
    }

    private fun setupPreviewSurface() {
        // Prepare the preview surface using TextureView
        val options = BarcodeScannerOptions.Builder()
            .build()
        barcodeScanner = BarcodeScanning.getClient(options!!)
        startBackgroundThread()
        previewSurface = Surface(textureView.surfaceTexture)
    }

    private fun initializeImageCapture() {
        // Create a CaptureRequest for image capture
        mPreviewRequestBuilder =
            mCameraDevice?.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
        mPreviewRequestBuilder?.addTarget(previewSurface!!)

        // Set up the ImageReader for capturing still images
//        mImageReader = ImageReader.newInstance(
//            1920, 1080, ImageFormat.JPEG, 1
//        )
//        BarcodeDetector.setImageReader(mImageReader);
//
//


        // Add your ImageReader listener to process the captured image
//        mImageReader!!.setOnImageAvailableListener({ reader ->
//            val image = reader.acquireLatestImage()
//            if (image != null) {
//                // Save or process the captured image
//                val outputFile =
//                    File(context.cacheDir, "captured_image_${System.currentTimeMillis()}.jpg")
//                val fileOutputStream = FileOutputStream(outputFile)
//                val buffer = image.planes[0].buffer
//                val bytes = ByteArray(buffer.remaining())
//                buffer.get(bytes)
//                fileOutputStream.write(bytes)
//                fileOutputStream.close()
//
//                // Notify that image has been captured
//                methodChannel.invokeMethod("onImageCaptured", outputFile.absolutePath)
//                image.close()
//            }
//        }, mBackgroundHandler)
    }

    private fun adjustPreviewAspectRatio() {
        // Get the aspect ratio of the camera resolution
        val displaySize = Point()
        val displayMetrics = context.resources.displayMetrics
        val cameraWidth = displayMetrics.widthPixels
        val cameraHeight = displayMetrics.heightPixels
        val cameraResolution = Size(cameraWidth, cameraHeight) // You should query the actual supported resolution

        val screenWidth = linearLayout.width
        val screenHeight = linearLayout.height

        val cameraAspectRatio = cameraResolution.height.toFloat() / cameraResolution.width.toFloat()
        val screenAspectRatio = screenHeight.toFloat() / screenWidth.toFloat()

        val layoutParams = textureView.layoutParams

        // Maintain the aspect ratio, clip the image if necessary
        if (cameraAspectRatio > screenAspectRatio) {
            layoutParams.width = (cameraHeight * cameraAspectRatio).toInt()
            layoutParams.height = cameraHeight
        } else {
            layoutParams.height = (cameraWidth / cameraAspectRatio).toInt()
            layoutParams.width = cameraWidth
        }

        // Update the layout
        textureView.layoutParams = layoutParams
    }

    private fun startPreview() {
        mPreviewRequestBuilder = mCameraDevice?.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)

//        val previewRequestBuilder =
//            cameraDevice?.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
//        val previewRequestBuilder = cameraDevice?.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
//        previewRequestBuilder?.addTarget(previewSurface!!)
//        mImageReader = ImageReader.newInstance(
//            1080, 1920,
//            ImageFormat.JPEG, 2
//        );
//        mImageReader!!.setOnImageAvailableListener(mOnImageAvailableListener, mBackgroundHandler);
//
//        previewRequestBuilder?.addTarget(mImageReader!!.surface)

        if (mPreviewSession == null) {

            mImageReader = ImageReader.newInstance(1080, 1920, ImageFormat.YUV_420_888, 2);
            BarcodeDetector.setImageReader(mImageReader);
            mImageReader!!.setOnImageAvailableListener(mOnImageAvailableListener,mBackgroundHandler)
            // Capture the image using the camera
//            cameraDevice?.createCaptureSession(
//                listOf(imageReader.surface),
//                object : CameraCaptureSession.StateCallback() {
//                    override fun onConfigured(session: CameraCaptureSession) {
//                        captureSession = session
//                        session.capture(previewRequestBuilder!!.build(), mCaptureCallback, mBackgroundHandler)
//                    }
//
//                    override fun onConfigureFailed(session: CameraCaptureSession) {
//                        Log.e("Camera2", "Failed to configure capture session")
//                    }
//                },
//                mBackgroundHandler
//            )


            // If session is null or closed, create a new capture session

            val surfaces = listOf(previewSurface!!, mImageReader!!.surface)

            mCameraDevice?.createCaptureSession(
                surfaces,
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        mPreviewSession = session

                        // Prepare the capture request

                        // Add both preview and ImageReader surfaces to the request
                        mPreviewRequestBuilder?.addTarget(previewSurface!!)
                        mPreviewRequestBuilder?.addTarget(mImageReader!!.surface)

                        try {
                            // Start the preview request with the capture session
                            mPreviewSession?.setRepeatingRequest(
                                mPreviewRequestBuilder!!.build(),
                                mCaptureCallback,
                                mBackgroundHandler
                            )
                        } catch (e: CameraAccessException) {
                            e.printStackTrace()
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        Log.e("Camera2", "Failed to configure capture session")
                    }
                },
                mBackgroundHandler
            )

//            cameraDevice?.createCaptureSession(
//                listOf(previewSurface!!),
//                object : CameraCaptureSession.StateCallback() {
//                    override fun onConfigured(session: CameraCaptureSession) {
//                        captureSession = session
//                        try {
//                            // Set up repeating request once the session is configured
//                            captureSession?.setRepeatingRequest(
//                                previewRequestBuilder!!.build(),
//                                mCaptureCallback,
//                                mBackgroundHandler
//                            )
//                        } catch (e: CameraAccessException) {
//                            e.printStackTrace()
//                        }
//                    }
//
//                    override fun onConfigureFailed(session: CameraCaptureSession) {
//                        Log.e("Camera2", "Failed to configure capture session")
//                    }
//                },
//                mBackgroundHandler
//            )
//
//            cameraDevice?.createCaptureSession(
//                listOf(previewSurface!!, mImageReader!!.surface),
//                object : CameraCaptureSession.StateCallback() {
//                    override fun onConfigured(session: CameraCaptureSession) {
//                        session.capture(previewRequestBuilder!!.build(), mCaptureCallback, mBackgroundHandler)
//                    }
//
//                    override fun onConfigureFailed(session: CameraCaptureSession) {
//                        Log.e("Camera2", "Failed to configure capture session")
//                    }
//                },
//                mBackgroundHandler
//            )




        } else {
            // Session is valid, set the repeating request on the current session
            try {
                mPreviewSession?.setRepeatingRequest(
                    mPreviewRequestBuilder!!.build(),
                    mCaptureCallback,
                    mBackgroundHandler
                )
            } catch (e: CameraAccessException) {
                e.printStackTrace()
            }
        }
    }

    private fun takePicture(result: MethodChannel.Result) {
        // Create a CaptureRequest for still image capture
        val captureRequestBuilder =
            mCameraDevice?.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
//        captureRequestBuilder?.addTarget(previewSurface!!)

        // Create an ImageReader to capture the image
        val imageReader = ImageReader.newInstance(
            1920, 1080, ImageFormat.JPEG, 1
        )
        captureRequestBuilder?.addTarget(imageReader.surface)

        // Add listener to process the captured image
        imageReader.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage()
            if (image != null) {
                // Save the image to a file
                val outputFile =
                    File(context.cacheDir, "captured_image_${System.currentTimeMillis()}.jpg")
                val fileOutputStream = FileOutputStream(outputFile)
                val buffer = image.planes[0].buffer
                val bytes = ByteArray(buffer.remaining())
                buffer.get(bytes)
                fileOutputStream.write(bytes)
                fileOutputStream.close()

                // Return image path to Flutter
                result.success(outputFile.absolutePath)
                image.close()
            }
        }, mBackgroundHandler)
//        imageReader.setOnImageAvailableListener(mOnImageAvailableListener,mBackgroundHandler)

        // Capture the image using the camera
        mCameraDevice?.createCaptureSession(
            listOf(imageReader.surface),
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    session.capture(captureRequestBuilder!!.build(), mCaptureCallback, mBackgroundHandler)
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e("Camera2", "Failed to configure capture session")
                }
            },
            mBackgroundHandler
        )
    }

    // Return the layout containing the camera preview
    override fun getView(): FrameLayout {
        return linearLayout
    }

    // Dispose of resources when no longer needed
    override fun dispose() {
        cameraExecutor.shutdown()
        mCameraDevice?.close()
    }

    // Handle method calls from Flutter
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "changeFlashMode" -> {
                val flashModeID = call.argument<Int>("flashModeID")!!
                changeFlashMode(flashModeID, result)
            }

            "switchCamera" -> {
                val cameraID = call.argument<Int>("cameraID")!!
                switchCamera(cameraID, result)
            }

            "pauseCamera" -> pauseCamera(result)
            "resumeCamera" -> resumeCamera(result)
            "getPlatformVersion" -> result.success("Android " + Build.VERSION.RELEASE)
            "takePicture" -> takePicture(result)
            "dispose" -> dispose()
            else -> result.notImplemented()
        }
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

    private fun changeFlashMode(flashModeID: Int, result: MethodChannel.Result) {
        // Flash mode: 0 - OFF, 1 - ON
        flashMode = flashModeID == 1

        if (flashMode) {
            Log.d("Camera2", "Flash turned ON")
        } else {
            Log.d("Camera2", "Flash turned OFF")
        }

        // Re-apply the capture request to toggle the flash mode
        mPreviewSession?.let {
            try {
               mPreviewRequestBuilder =
                    mCameraDevice?.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                mPreviewRequestBuilder?.addTarget(previewSurface!!)
//                mImageReader = ImageReader.newInstance(
//                    1080, 1920,
//                    ImageFormat.JPEG, 2
//                );
//                mImageReader!!.setOnImageAvailableListener(mOnImageAvailableListener, mBackgroundHandler);
//
//                previewRequestBuilder?.addTarget(mImageReader!!.surface)


                // Set the flash mode based on the current state
                if (flashMode) {
                    mPreviewRequestBuilder?.set(
                        CaptureRequest.FLASH_MODE,
                        CaptureRequest.FLASH_MODE_TORCH
                    )
                } else {
                    mPreviewRequestBuilder?.set(
                        CaptureRequest.FLASH_MODE,
                        CaptureRequest.FLASH_MODE_OFF
                    )
                }

                // Apply the updated request to the capture session
                it.setRepeatingRequest(
                    mPreviewRequestBuilder!!.build(),
                    mCaptureCallback,
                    Handler(Looper.getMainLooper())
                )
                result.success(true)
            } catch (e: CameraAccessException) {
                e.printStackTrace()
                result.error("FLASH_MODE_ERROR", "Failed to change flash mode", e)
            }
        }
    }

    private fun switchCamera(cameraId: Int, result: MethodChannel.Result) {
        // Find the camera manager and available camera IDs
        cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraIdList = cameraManager.cameraIdList

        // If cameraId is 1, switch to front camera, otherwise to rear camera (cameraId 0)
        val newCameraId = if (cameraId == 1 && cameraIdList.size > 1) {
            cameraIdList[1] // Front camera
        } else {
            cameraIdList[0] // Rear camera (default)
        }

        // Close the current camera and reopen the new one
        mCameraDevice?.close()
        mCameraDevice = null

        cameraManager.openCamera(newCameraId, object : CameraDevice.StateCallback() {
            override fun onOpened(camera: CameraDevice) {
                mCameraDevice = camera
                setupPreviewSurface() // Set up the preview surface for the new camera
                startPreview() // Start the preview for the new camera
                result.success(true)
            }

            override fun onDisconnected(camera: CameraDevice) {
                mCameraDevice?.close()
            }

            override fun onError(camera: CameraDevice, error: Int) {
                Log.e("Camera2", "Error opening camera: $error")
                result.error("CAMERA_SWITCH_ERROR", "Failed to switch camera", error)
            }
        }, mBackgroundHandler)
    }

    private fun pauseCamera(result: MethodChannel.Result) {
        // Pause the camera preview (freeze the feed)
        isCameraPaused = true
//        mPreviewSession?.stopRepeating() // Stop the camera preview stream
        stop()
        // Notify that the camera has been paused
        result.success(true)
    }

    private fun resumeCamera(result: MethodChannel.Result) {
        // Resume the camera preview (unfreeze the feed)
        if (isCameraPaused) {
            isCameraPaused = false
            startPreview() // Restart the preview session
            result.success(true)
        } else {
            // If the camera is not paused, return false
            result.success(false)
        }
    }


    private fun closeCamera() {
        try {
            mCameraOpenCloseLock.acquire()
            if (null != mPreviewSession) {
                mPreviewSession!!.close()
                mPreviewSession = null
            }
            if (null != mCameraDevice) {
                mCameraDevice!!.close()
                mCameraDevice = null
            }

            if (null != mImageReader) {
                mImageReader!!.close()
                BarcodeDetector.setImageReader(null)
                mImageReader = null
            }
            try {
                if (barcodeScanner != null) {
                    barcodeScanner.close()
                }
            } catch (e: Exception) {
                println("Error to closing detector: " + e.message)
            }
        } catch (e: InterruptedException) {
            throw RuntimeException("Interrupted while trying to lock camera closing.", e)
        } finally {
            mCameraOpenCloseLock.release()
        }
    }

    fun stop() {
        closeCamera()
        stopBackgroundThread()
    }

    private fun stopBackgroundThread() {
        mBackgroundThread!!.quitSafely()
        try {
            mBackgroundThread!!.join()
            mBackgroundThread = null
            mBackgroundHandler = null
        } catch (e: InterruptedException) {
            e.printStackTrace()
        }
    }

    private fun startBackgroundThread() {
        mBackgroundThread = HandlerThread("CameraBackground")
        mBackgroundThread!!.start()
        mBackgroundHandler = object : Handler(mBackgroundThread!!.looper) {
            override fun handleMessage(msg: Message) {
                super.handleMessage(msg)
                when (msg.what) {
                    MSG_CAPTURE_PICTURE_WHEN_FOCUS_TIMEOUT -> {
                        mState = STATE_PICTURE_TAKEN
                        captureStillPicture()
                    }

                    else -> {}
                }
            }
        }
    }

    private val mCaptureCallback
            : CameraCaptureSession.CaptureCallback = object : CameraCaptureSession.CaptureCallback() {
        private fun process(result: CaptureResult) {
            when (mState) {

                STATE_PREVIEW -> {
//                    val afState = result[CaptureResult.CONTROL_AF_STATE]
//                    Log.i(TAG, "STATE_PREVIEW afState: $afState")
                }
                STATE_WAITING_LOCK -> {
                    val afState = result[CaptureResult.CONTROL_AF_STATE]
                    Log.i(TAG, "STATE_WAITING_LOCK afState: $afState")
                    if (afState == null) {
                        mState = STATE_PICTURE_TAKEN
                        captureStillPicture()
                    } else if (CaptureResult.CONTROL_AF_STATE_FOCUSED_LOCKED == afState ||
                        CaptureResult.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED == afState
                    ) {
                        // CONTROL_AE_STATE can be null on some devices
                        val aeState = result[CaptureResult.CONTROL_AE_STATE]
                        if (aeState == null ||
                            aeState == CaptureResult.CONTROL_AE_STATE_CONVERGED
                        ) {
                            mState = STATE_PICTURE_TAKEN
                            captureStillPicture()
                        } else {
                            runPrecaptureSequence()
                        }
                    }
                }

                STATE_WAITING_PRECAPTURE -> {
                    // CONTROL_AE_STATE can be null on some devices
                    val aeState = result[CaptureResult.CONTROL_AE_STATE]
                    if (aeState == null || aeState == CaptureResult.CONTROL_AE_STATE_PRECAPTURE || aeState == CaptureRequest.CONTROL_AE_STATE_FLASH_REQUIRED) {
                        mState = STATE_WAITING_NON_PRECAPTURE
                    }
                }

                STATE_WAITING_NON_PRECAPTURE -> {
                    // CONTROL_AE_STATE can be null on some devices
                    val aeState = result[CaptureResult.CONTROL_AE_STATE]
                    if (aeState == null || aeState != CaptureResult.CONTROL_AE_STATE_PRECAPTURE) {
                        mState = STATE_PICTURE_TAKEN
                        captureStillPicture()
                    }
                }
            }
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
            process(result)
//            if (hasBarcodeReader) {
//                if (previewFlashMode === 'A') {
//                    val aeState = result.get(CaptureResult.CONTROL_AE_STATE)
//                    if (aeState != null) {
//                        if (aeState == CaptureResult.CONTROL_AE_STATE_FLASH_REQUIRED) {
//                            changeFlashMode('O')
//                            //                            updateFlash(mPreviewRequestBuilder);
//                        }
//                    }
//                }
//            } else {
//                process(result)
//            }
        }
    }

    private fun toInputImage(image: Image): InputImage {
        val plane = image.planes[0]
        val buffer: ByteBuffer = plane.buffer
        val data = ByteArray(buffer.remaining())
        buffer.get(data)

        // ML Kit expects NV21 format for the image
        return InputImage.fromByteArray(data, image.width, image.height, 0, InputImage.IMAGE_FORMAT_NV21)
    }

    // Handle detected barcode data
    private fun handleDetectedBarcode(barcode: Barcode) {
        // Extract barcode details and handle the results
        val valueType = barcode.valueType
        when (valueType) {
            Barcode.TYPE_WIFI -> {
                val ssid = barcode.wifi?.ssid
                val password = barcode.wifi?.password
                Log.d("Barcode", "WiFi SSID: $ssid, Password: $password")
            }
            Barcode.TYPE_URL -> {
                val url = barcode.url?.url
                Log.d("Barcode", "URL: $url")
            }
            Barcode.TYPE_TEXT -> {
                val rawValue = barcode.displayValue
                Log.d("Barcode", "Text: $rawValue")
            }
            else -> {
                // Handle other barcode types
                Log.d("Barcode", "Other Barcode: ${barcode.displayValue}")
            }
        }
    }

    private fun captureStillPicture() {
        try {
            removeCaptureMessage()
            if (null == getActivity(context) || null == mCameraDevice) {
                return
            }
            // This is the CaptureRequest.Builder that we use to take a picture.
            mPreviewRequestBuilder =
                mCameraDevice!!.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
            mPreviewRequestBuilder!!.addTarget(mImageReader!!.surface)

            // Use the same AE and AF modes as the preview.
//            captureBuilder.set(CaptureRequest.CONTROL_AF_MODE,
//                CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
//            updateAutoFocus();
//            updateFlash(captureBuilder)

            // Orientation
            val rotation: Int = getActivity(context)!!.getWindowManager().getDefaultDisplay().getRotation()
//            captureBuilder.set(CaptureRequest.JPEG_ORIENTATION, getOrientation(rotation))

            val CaptureCallback
                    : CameraCaptureSession.CaptureCallback = object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureCompleted(
                    session: CameraCaptureSession,
                    request: CaptureRequest,
                    result: TotalCaptureResult
                ) {
                    unlockFocus()
                }
            }

            mPreviewSession!!.stopRepeating()
            mPreviewSession!!.capture(mPreviewRequestBuilder!!.build(), CaptureCallback, mBackgroundHandler)
        } catch (e: CameraAccessException) {
            e.printStackTrace()
        }
    }

    private fun runPrecaptureSequence() {
        try {
            // This is how to tell the camera to trigger.
            mPreviewRequestBuilder!!.set(
                CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER,
                CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER_START
            )
            // Tell #mCaptureCallback to wait for the precapture sequence to be set.
            mState = STATE_WAITING_PRECAPTURE
            mPreviewSession!!.capture(mPreviewRequestBuilder!!.build(), mCaptureCallback, mBackgroundHandler)
        } catch (e: CameraAccessException) {
            e.printStackTrace()
        }
    }


    private fun unlockFocus() {
        try {
            // Reset the auto-focus trigger
            mPreviewRequestBuilder!!.set(
                CaptureRequest.CONTROL_AF_TRIGGER,
                CameraMetadata.CONTROL_AF_TRIGGER_CANCEL
            )
            mPreviewSession!!.capture(
                mPreviewRequestBuilder!!.build(), mCaptureCallback,
                mBackgroundHandler
            )

//            updateAutoFocus()
//            updateFlash(mPreviewRequestBuilder)
            // After this, the camera will go back to the normal state of preview.
            mState = STATE_PREVIEW
            mPreviewRequestBuilder!!.set(
                CaptureRequest.CONTROL_AF_TRIGGER,
                CaptureRequest.CONTROL_AF_TRIGGER_IDLE
            )
            if (mPreviewRequest != null) {
                mPreviewSession!!.setRepeatingRequest(
                    mPreviewRequest!!, mCaptureCallback,
                    mBackgroundHandler
                )
            }
        } catch (e: CameraAccessException) {
            e.printStackTrace()
        }
    }

    private fun removeCaptureMessage() {
        if (mBackgroundHandler != null) {
            mBackgroundHandler!!.removeMessages(MSG_CAPTURE_PICTURE_WHEN_FOCUS_TIMEOUT)
        }
    }
}