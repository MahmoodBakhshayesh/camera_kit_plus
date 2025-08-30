import Flutter
import UIKit

import Foundation
import AVFoundation
import AudioToolbox
import MLKitTextRecognition
import MLKitCommon
import MLKitVision

@available(iOS 10.0, *)
class CameraKitOcrView: NSObject, FlutterPlatformView, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var _view: UIView
    var channel: FlutterMethodChannel
    let frame: CGRect
    //    var hasBarcodeReader:Bool!
    var imageSavePath:String!
    var isCameraVisible:Bool! = true
    var initCameraFinished:Bool! = false
    var isFillScale:Bool!
    var flashMode:AVCaptureDevice.FlashMode!
    var cameraPosition: AVCaptureDevice.Position! = .back
    var previewView : UIView!
    var videoDataOutput: AVCaptureVideoDataOutput!
    var videoDataOutputQueue: DispatchQueue!
    var photoOutput: AVCapturePhotoOutput?
    var previewLayer:AVCaptureVideoPreviewLayer!
    var captureDevice : AVCaptureDevice!
    let session = AVCaptureSession()
    var textRecognizer : TextRecognizer?
    var flutterResultTakePicture:FlutterResult!
    var flutterResultOcr:FlutterResult!
    var orientation : UIImage.Orientation!
    private var isCapturing = false

    /// 0:camera 1:barcodeScanner 2:ocrReader
    var usageMode:Int = 0

    // Zoom
    private var minZoomFactor: CGFloat = 1.0
    private var lastZoomFactor: CGFloat = 1.0
    private var maxZoomFactor: CGFloat {
        // Cap practical zoom to 8x to avoid ugly noise; raise if you want
        return min(self.captureDevice?.activeFormat.videoMaxZoomFactor ?? 1.0, 8.0)
    }

    // Forced OCR rotation (0..3 quarter turns)
    private var forcedQuarterTurns: Int = 0

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        _view = UIView()
        self.channel = FlutterMethodChannel(name:"artemis_camera_kit",binaryMessenger: messenger!)
        self.frame = frame

        super.init()
        self.flashMode = .off // default to safe value

        self.channel.setMethodCallHandler(handle)
        createNativeView(view: _view)
        setupCamera()
        setupAVCapture()
        channel = FlutterMethodChannel(name: "camera_kit_plus", binaryMessenger: messenger!)
        channel.setMethodCallHandler(handle)
    }

    func view() -> UIView {
        if previewView == nil {
            self.previewView = UIView(frame: frame)
            // previewView.contentMode = .scaleAspectFill
        }
        previewView.isUserInteractionEnabled = true
        attachZoomGesturesIfNeeded()
        return previewView
    }

    func createNativeView(view _view: UIView){
        _view.backgroundColor = UIColor.blue
        let nativeLabel = UILabel()
        nativeLabel.text = "Native text from iOS"
        nativeLabel.textColor = UIColor.white
        nativeLabel.textAlignment = .center
        nativeLabel.frame = CGRect(x: 0, y: 0, width: 180, height: 48.0)
        _view.addSubview(nativeLabel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments
        let myArgs = args as? [String: Any]
        switch call.method {
        case "getCameraPermission":
            self.getCameraPermission(flutterResult: result)

        case "initCamera":
            // no-op; you already call setup in init
            result(true)

        case "changeFlashMode":
            // wire your flash mapping here if needed
            result(true)

        case "changeCameraVisibility":
            let visibility = (myArgs?["visibility"] as? Bool) ?? true
            self.changeCameraVisibility(visibility: visibility)
            result(true)

        case "pauseCamera":
            self.pauseCamera(); result(true)

        case "resumeCamera":
            self.resumeCamera(); result(true)

        case "takePicture":
            let path = myArgs?["path"] as? String
            self.takePicture(path:path,flutterResult: result)

        case "dispose":
            result(true)

        case "setZoom":
            if let z = myArgs?["zoom"] as? Double {
                self.setZoom(factor: CGFloat(z), animated: true)
                result(true)
            } else {
                result(FlutterError(code: "bad_args", message: "zoom (Double) required", details: nil))
            }

        case "resetZoom":
            self.setZoom(factor: 1.0, animated: true)
            result(true)

        case "setOcrRotation": // expects degrees: 0,90,180,270
            let deg = (myArgs?["degrees"] as? Int) ?? 0
            let turns = ((deg / 90) % 4 + 4) % 4
            self.forcedQuarterTurns = turns
            result(true)

        case "clearOcrRotation":
            self.forcedQuarterTurns = 0
            result(true)

        default:
            result(false)
        }
    }

    func getCameraPermission(flutterResult:  @escaping FlutterResult) {
        if AVCaptureDevice.authorizationStatus(for: .video) ==  .authorized {
            flutterResult(true as Bool)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                AVCaptureDevice.requestAccess(for: .video, completionHandler: { (granted: Bool) in
                    flutterResult(granted)
                })
            }
        }
    }

    func setupCamera(){
        self.usageMode = 2
        self.isFillScale = true
        self.cameraPosition = .back
        self.flashMode = .off
        textRecognizer = TextRecognizer.textRecognizer()
        self.setupAVCapture()
    }

    func initCamera( flashMode: Int, fill: Bool, barcodeTypeID: Int, cameraID: Int, modeID: Int) {
        print("Usage Mode set to "+String(modeID))
        self.usageMode = modeID
        self.isFillScale = fill
        self.cameraPosition = cameraID == 0 ? .back : .front
        textRecognizer = TextRecognizer.textRecognizer()
        self.setupAVCapture()
    }

    @available(iOS 10.0, *)
    func setupAVCapture(){
        session.sessionPreset = AVCaptureSession.Preset.hd1920x1080
        guard let device = AVCaptureDevice
            .default(AVCaptureDevice.DeviceType.builtInWideAngleCamera,
                     for: .video,
                     position: cameraPosition) else {
            return
        }
        captureDevice = device

        beginSession()
        // changeFlashMode()
    }

    func beginSession(isFirst: Bool = true){
        var deviceInput: AVCaptureDeviceInput!

        do {
            deviceInput = try AVCaptureDeviceInput(device: captureDevice)
            guard deviceInput != nil else {
                print("error: cant get deviceInput")
                return
            }

            if self.session.canAddInput(deviceInput){
                self.session.addInput(deviceInput)
            }
            lastZoomFactor = 1.0
            if let pConn = photoOutput?.connection(with: .video) {
                pConn.isEnabled = true
            }

            orientation = imageOrientation(fromDevicePosition: cameraPosition)

            // OCR video output
            videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput.alwaysDiscardsLateVideoFrames = true

            videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue")
            videoDataOutput.setSampleBufferDelegate(self, queue:self.videoDataOutputQueue)
            if session.canAddOutput(videoDataOutput!){
                session.addOutput(videoDataOutput)
            }
            videoDataOutput.connection(with: .video)?.isEnabled = true

            AudioServicesDisposeSystemSoundID(1108)

            // Photo output
            photoOutput = AVCapturePhotoOutput()
            photoOutput?.isHighResolutionCaptureEnabled = true
            photoOutput?.setPreparedPhotoSettingsArray(
                [AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecJPEG])],
                completionHandler: nil
            )
            if session.canAddOutput(photoOutput!){
                session.addOutput(photoOutput!)
            }

            // Preview
            previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
            previewLayer.videoGravity = self.isFillScale == true ? .resizeAspectFill : .resizeAspect

            startSession(isFirst: isFirst)

        } catch let error as NSError {
            deviceInput = nil
            print("error: \(error.localizedDescription)")
        }
    }

    func startSession(isFirst: Bool) {
        DispatchQueue.main.async {
            let rootLayer :CALayer = self.previewView.layer
            rootLayer.masksToBounds = true
            if(rootLayer.bounds.size.width != 0 && rootLayer.bounds.size.width != 0){
                self.previewLayer.frame = rootLayer.bounds
                rootLayer.addSublayer(self.previewLayer)
                self.session.startRunning()
                if isFirst == true {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                        self.initCameraFinished = true
                    }
                }
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    self.startSession(isFirst: isFirst)
                }
            }
        }
    }

    func setFlashMode(mode: AVCaptureDevice.TorchMode){
        // torch stub (your earlier code had it disabled)
    }

    func changeFlashMode(modeID: Int,result:  @escaping FlutterResult){
        setFlashMode(mode: (modeID == 2) ?(.auto):(modeID == 1 ? (.on) : (.off)))
        result(true)
    }

    func pauseCamera() {
        if self.initCameraFinished == true {
            self.stopCamera()
            self.isCameraVisible = false
        }
    }

    func resumeCamera() {
        if  self.initCameraFinished == true {
            if !self.session.isRunning { self.session.startRunning() }
            self.isCameraVisible = true
        }
    }

    func stopCamera(){
        if session.isRunning {
            session.stopRunning()
        }
    }

    func changeCameraVisibility(visibility:Bool){
        if visibility == true {
            if self.isCameraVisible == false {
                if !self.session.isRunning { self.session.startRunning() }
                self.isCameraVisible = true
            }
        } else {
            if self.isCameraVisible == true {
                self.stopCamera()
                self.isCameraVisible = false
            }
        }
    }

    // -------------------------
    // FIXED takePicture + modern delegate
    // -------------------------
    func takePicture(path: String?, flutterResult: @escaping FlutterResult) {
        guard let photoOutput = self.photoOutput else {
            flutterResult(FlutterError(code: "-100", message: "Photo output not configured", details: nil))
            return
        }
        guard let device = self.captureDevice else {
            flutterResult(FlutterError(code: "-104", message: "Camera device not ready", details: nil))
            return
        }
        guard initCameraFinished == true else {
            flutterResult(FlutterError(code: "-105", message: "Camera not initialized yet", details: nil))
            return
        }
        guard !isCapturing else {
            flutterResult(FlutterError(code: "-106", message: "Capture in progress", details: nil))
            return
        }
        isCapturing = true

        self.imageSavePath = path
        self.flutterResultTakePicture = flutterResult

        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])

        // Only set flash if valid and supported
        if let mode = self.flashMode,
           device.isFlashAvailable,
           photoOutput.supportedFlashModes.contains(mode) {
            settings.flashMode = mode
        }

        if photoOutput.isHighResolutionCaptureEnabled {
            settings.isHighResolutionPhotoEnabled = true
        }

        // Match photo orientation to the preview (no force unwraps)
        if let conn = photoOutput.connection(with: .video) {
            if let prev = previewLayer?.connection, prev.isVideoOrientationSupported {
                conn.videoOrientation = prev.videoOrientation
            }
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = (cameraPosition == .front)
            }
        }
        
        // Make sure the session is running
        if !self.session.isRunning { self.session.startRunning() }

        // Wait until the photo connection is active, then capture
        self.waitForActivePhotoConnection { conn in
            guard let conn = conn else {
                self.isCapturing = false
                flutterResult(FlutterError(code: "-107",
                                           message: "No active/enabled video connection",
                                           details: "Waited for connection but it never became active"))
                return
            }

            // Sync orientation/mirroring to preview (same as before)
            if let prev = self.previewLayer?.connection, prev.isVideoOrientationSupported {
                conn.videoOrientation = prev.videoOrientation
            }
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = (self.cameraPosition == .front)
            }

            DispatchQueue.main.async {
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }

        // Fire on main
//        DispatchQueue.main.async {
//            photoOutput.capturePhoto(with: settings, delegate: self)
//        }
    }

    // Modern delegate — single entry point
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        defer { isCapturing = false }

        if let error = error {
            self.flutterResultTakePicture?(FlutterError(code: "-101", message: error.localizedDescription, details: nil))
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            self.flutterResultTakePicture?(FlutterError(code: "-102", message: "No photo data", details: nil))
            return
        }

        _ = self.saveImage(image: image)

        // Re-assert zoom (in case capture nudged it)
        if let device = self.captureDevice {
            do {
                try device.lockForConfiguration()
                let clamped = max(1.0, min(device.videoZoomFactor, device.activeFormat.videoMaxZoomFactor))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch { /* ignore */ }
        }
    }
    
    // Save to the provided path (or Documents/pic.jpg) and return the path via FlutterResult
    func saveImage(image: UIImage) -> Bool {
        // Encode
        guard let data = image.jpegData(compressionQuality: 0.95) ?? image.pngData() else {
            self.flutterResultTakePicture?(FlutterError(code: "-103a", message: "Could not encode image", details: nil))
            return false
        }

        // Resolve destination URL
        let url: URL = {
            if let p = self.imageSavePath, !p.isEmpty {
                return URL(fileURLWithPath: p)
            } else {
                let dir = (try? FileManager.default.url(for: .documentDirectory,
                                                        in: .userDomainMask,
                                                        appropriateFor: nil,
                                                        create: true))
                          ?? URL(fileURLWithPath: NSTemporaryDirectory())
                return dir.appendingPathComponent("pic.jpg")
            }
        }()

        // Ensure folder exists, write atomically, then callback
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            self.flutterResultTakePicture?(url.path)  // success -> send path back
            return true
        } catch {
            print("saveImage error: \(error)")
            self.flutterResultTakePicture?(FlutterError(code: "-103", message: error.localizedDescription, details: nil))
            return false
        }
    }

    
    /// Wait until AVCapturePhotoOutput has an active + enabled video connection,
    /// then call back with it (or nil on timeout).
    private func waitForActivePhotoConnection(
        maxAttempts: Int = 20,
        delayMs: Int = 50,
        _ ready: @escaping (AVCaptureConnection?) -> Void
    ) {
        var attempts = 0
        func tick() {
            attempts += 1
            guard let p = self.photoOutput,
                  let conn = p.connection(with: .video) else {
                if attempts >= maxAttempts { ready(nil); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { tick() }
                return
            }
            if conn.isEnabled && conn.isActive {
                ready(conn)
            } else if attempts >= maxAttempts {
                ready(nil)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { tick() }
            }
        }
        tick()
    }


    // -------------------------
    // OCR (camera frames)
    // -------------------------
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let tr = textRecognizer else { return }

        let visionImage = VisionImage(buffer: sampleBuffer)
        // base orientation from camera (your existing cached value)
        let base = imageOrientation(fromDevicePosition: cameraPosition)
        // apply forced quarter turns
        visionImage.orientation = rotate(base, turns: forcedQuarterTurns)

        do {
            let result = try tr.results(in: visionImage)   // non-optional MLKit.Text
            let txt = result.text
            if !txt.isEmpty {
                var listLineModel: [LineModel] = []

                for b in result.blocks {
                    for l in b.lines {
                        let lineModel : LineModel = LineModel()
                        lineModel.text = l.text
                        for c in l.cornerPoints {
                            lineModel.cornerPoints.append(CornerPointModel(x: c.cgPointValue.x, y: c.cgPointValue.y))
                        }
                        listLineModel.append(lineModel)
                    }
                }

                self.onTextRead(text: txt, values: listLineModel, path: "", orientation:  visionImage.orientation.rawValue)

            } else {
                self.onTextRead(text: "", values: [], path: "", orientation:  nil)
            }

        } catch {
            print("can't fetch result: \(error)")
        }
    }

    func onBarcodeRead(barcode: String) {
        channel.invokeMethod("onBarcodeRead", arguments: barcode)
    }

    func onTextRead(text: String, values: [LineModel], path: String?, orientation: Int?) {
        let data = OcrData(text: text, path: path, orientation: orientation, lines: values)
        let jsonEncoder = JSONEncoder()
        do {
            let jsonData = try jsonEncoder.encode(data)
            let json = String(data: jsonData, encoding: .utf8)
            channel.invokeMethod("onTextRead", arguments: json)
        } catch {
            print("JSON encode error: \(error)")
        }
    }

    func textRead(text: String, values: [LineModel], path: String?, orientation: Int?) {
        let data = OcrData(text: text, path: path, orientation: orientation, lines: values)
        let jsonEncoder = JSONEncoder()
        do {
            let jsonData = try jsonEncoder.encode(data)
            let json = String(data: jsonData, encoding: .utf8)
            flutterResultOcr?(json)
        } catch {
            flutterResultOcr?(FlutterError(code:"-200", message:"JSON encode error", details:error.localizedDescription))
        }
    }

    // -------------------------
    // Still image OCR
    // -------------------------
    func processImageFromPath(path:String,flutterResult:  @escaping FlutterResult){
        let fileURL = URL(fileURLWithPath: path)
        do {
            self.flutterResultOcr = flutterResult
            let imageData = try Data(contentsOf: fileURL)
            let image = UIImage(data: imageData)
            if image == nil { return }
            let visionImage = VisionImage(image: image!)
            // Force rotation knob applies to stills too
            visionImage.orientation = rotate(image!.imageOrientation, turns: forcedQuarterTurns)
            processImage(visionImage: visionImage, selectedImagePath: path)
        } catch {
            print("Error loading image : \(error)")
        }
    }

    func processImage(visionImage: VisionImage, image: UIImage? = nil, selectedImagePath : String? = nil) {
        if textRecognizer != nil {
            if let ui = image {
                // override orientation for still images too
                visionImage.orientation = rotate(ui.imageOrientation, turns: forcedQuarterTurns)
            } else {
                // if coming from buffer and caller pre-set orientation, ensure it's rotated
                visionImage.orientation = rotate(visionImage.orientation, turns: forcedQuarterTurns)
            }
            let path : String? = selectedImagePath

            textRecognizer?.process(visionImage) { result, error in
                guard error == nil, let result = result else {
                    self.textRead(text: "Error: " + error.debugDescription, values: [], path: "", orientation: nil)
                    return
                }

                if !result.text.isEmpty {
                    var listLineModel: [LineModel] = []
                    for b in result.blocks {
                        for l in b.lines{
                            let lineModel : LineModel = LineModel()
                            lineModel.text = l.text
                            for c in l.cornerPoints {
                                lineModel.cornerPoints.append(CornerPointModel(x: c.cgPointValue.x, y: c.cgPointValue.y))
                            }
                            listLineModel.append(lineModel)
                        }
                    }

                    self.textRead(text: result.text, values: listLineModel, path: path, orientation:  visionImage.orientation.rawValue)
                } else {
                    self.textRead(text: "", values: [], path: path, orientation:  nil)
                }
            }
        }
    }

    // -------------------------
    // Zoom gestures
    // -------------------------
    private func attachZoomGesturesIfNeeded() {
        if let grs = previewView.gestureRecognizers, grs.isEmpty == false { return }

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        previewView.addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTapResetZoom))
        doubleTap.numberOfTapsRequired = 2
        previewView.addGestureRecognizer(doubleTap)
    }

    @objc private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        guard let device = self.captureDevice else { return }

        switch pinch.state {
        case .began:
            lastZoomFactor = device.videoZoomFactor

        case .changed:
            var newFactor = lastZoomFactor * pinch.scale
            newFactor = max(minZoomFactor, min(newFactor, maxZoomFactor))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = newFactor
                device.unlockForConfiguration()
            } catch {
                print("Zoom lock error: \(error)")
            }

        case .ended, .cancelled, .failed:
            // Clamp & optionally smooth
            let target = max(minZoomFactor, min(device.videoZoomFactor, maxZoomFactor))
            do {
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: target, withRate: 8.0) // smooth snap
                device.unlockForConfiguration()
            } catch {
                print("Zoom end error: \(error)")
            }
            lastZoomFactor = target

        default: break
        }
    }

    @objc private func handleDoubleTapResetZoom() {
        setZoom(factor: 1.0, animated: true)
    }

    private func setZoom(factor: CGFloat, animated: Bool = true) {
        guard let device = self.captureDevice else { return }
        let clamped = max(minZoomFactor, min(factor, maxZoomFactor))
        do {
            try device.lockForConfiguration()
            if animated {
                device.ramp(toVideoZoomFactor: clamped, withRate: 8.0)
            } else {
                device.videoZoomFactor = clamped
            }
            device.unlockForConfiguration()
            lastZoomFactor = clamped
        } catch {
            print("setZoom error: \(error)")
        }
    }

    // -------------------------
    // Orientation helpers for forced OCR rotation
    // -------------------------
    private func rotate90CW(_ o: UIImage.Orientation) -> UIImage.Orientation {
        switch o {
        case .up: return .right
        case .right: return .down
        case .down: return .left
        case .left: return .up
        case .upMirrored: return .rightMirrored
        case .rightMirrored: return .downMirrored
        case .downMirrored: return .leftMirrored
        case .leftMirrored: return .upMirrored
        @unknown default: return o
        }
    }

    private func rotate(_ o: UIImage.Orientation, turns: Int) -> UIImage.Orientation {
        let t = ((turns % 4) + 4) % 4
        var cur = o
        for _ in 0..<t { cur = rotate90CW(cur) }
        return cur
    }
    
    // MARK: - Orientation helpers

    private func interfaceOrientation() -> UIInterfaceOrientation {
        if #available(iOS 13.0, *) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                return scene.interfaceOrientation
            }
        } else {
            // Fallback on earlier versions
        }
        // Fallback (older iOS)
        return UIApplication.shared.statusBarOrientation
    }

    private func currentUIOrientation() -> UIDeviceOrientation {
        let io = interfaceOrientation()
        switch io {
        case .portrait:             return .portrait
        case .portraitUpsideDown:   return .portraitUpsideDown
        case .landscapeLeft:        return .landscapeRight   // flipped when mapping UI to device
        case .landscapeRight:       return .landscapeLeft
        default:                    return .portrait
        }
    }

    /// Maps device/UI orientation + camera position to UIImage.Orientation for ML Kit.
    public func imageOrientation(
        fromDevicePosition devicePosition: AVCaptureDevice.Position = .back
    ) -> UIImage.Orientation {
        var deviceOrientation = UIDevice.current.orientation
        if deviceOrientation == .faceDown || deviceOrientation == .faceUp || deviceOrientation == .unknown {
            deviceOrientation = currentUIOrientation()
        }
        switch deviceOrientation {
        case .portrait:
            return devicePosition == .front ? .leftMirrored : .right
        case .landscapeLeft:
            return devicePosition == .front ? .downMirrored : .up
        case .portraitUpsideDown:
            return devicePosition == .front ? .rightMirrored : .left
        case .landscapeRight:
            return devicePosition == .front ? .upMirrored : .down
        case .faceDown, .faceUp, .unknown:
            return .up
        @unknown default:
            return .up
        }
    }

}

