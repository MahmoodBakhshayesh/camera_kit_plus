import Flutter
import UIKit

import Foundation
import AVFoundation
import AudioToolbox
import MLKitTextRecognition
import MLKitCommon
import MLKitVision

@available(iOS 13.0, *)
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
    private var overlayView: UIView!
    private let overlayLayer = CAShapeLayer()
    private var lastFrameImageSize: CGSize = .zero //

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

    // ===== Macro =====
    private var isMacroEnabled: Bool = false

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
        channel = FlutterMethodChannel(name: "camera_kit_plus", binaryMessenger: messenger!)
        channel.setMethodCallHandler(handle)
    }

    func view() -> UIView {
        if previewView == nil {
            self.previewView = UIView(frame: frame)
        }
        previewView.isUserInteractionEnabled = true
        attachZoomGesturesIfNeeded()
        if overlayView == nil {
            overlayView = UIView(frame: previewView.bounds)
            overlayView.backgroundColor = .clear
            overlayView.isUserInteractionEnabled = false
            overlayLayer.strokeColor = UIColor.systemYellow.cgColor
            overlayLayer.fillColor = UIColor.clear.cgColor
            overlayLayer.lineWidth = 2.0
            overlayLayer.lineJoin = .round
            overlayLayer.lineCap = .round
            overlayView.layer.addSublayer(overlayLayer)
            previewView.addSubview(overlayView)
        }
        return previewView
    }
    
    private func layoutOverlaysToPreviewBounds() {
        guard overlayView != nil else { return }
        overlayView.frame = previewView.bounds
        overlayLayer.frame = overlayView.bounds
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
            result(true)

        case "changeFlashMode":
            let mode = (myArgs?["flashModeID"] as? Int)!
            changeFlashMode(modeID: mode, result: result)
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
            let path = (myArgs?["path"] as? String)!
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

        case "setOcrRotation":
            let deg = (myArgs?["degrees"] as? Int) ?? 0
            let turns = ((deg / 90) % 4 + 4) % 4
            self.forcedQuarterTurns = turns
            result(true)

        case "clearOcrRotation":
            self.forcedQuarterTurns = 0
            result(true)

        // ===== New: Macro toggle from Flutter =====
        case "setMacro":
            let enabled = (myArgs?["enabled"] as? Bool) ?? false
            self.setMacro(enabled: enabled)
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

    // Prefer virtual multi-camera when available (auto lens switching), else plain wide-angle
    @available(iOS 13.0, *)
    private func bestBackCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInUltraWideCamera,       // iPhone Pro models
                .builtInTripleCamera,       // iPhone Pro models
                .builtInDualWideCamera,     // many iPhones
                .builtInWideAngleCamera     // fallback
            ],
            mediaType: .video,
            position: .back
        )
        return discovery.devices.first
    }

    @available(iOS 13.0, *)
    func setupAVCapture(){
        session.sessionPreset = AVCaptureSession.Preset.hd1920x1080

        // pick best back camera
            if cameraPosition == .back, let dev = bestBackCamera() {
                captureDevice = dev
            } else if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) {
                captureDevice = dev
            } else {
                return
            }


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

            // Apply focus/AF settings (macro-aware)
            applyFocusConfiguration()

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
                self.layoutOverlaysToPreviewBounds()

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

    /// Sets continuous torch for preview, and updates the still-photo flash mode to match.
    /// Pass .off / .on / .auto (AVCaptureDevice.TorchMode)
    func setFlashMode(mode: AVCaptureDevice.TorchMode) {
        // 1) Keep your photo flash mode in sync for still captures
        switch mode {
        case .on:   self.flashMode = .on
        case .auto: self.flashMode = .auto
        default:    self.flashMode = .off
        }

        // 2) Apply torch for the live preview (rear camera only)
        guard let device = self.captureDevice,
              device.hasTorch,
              self.cameraPosition == .back
        else {
            // Front camera or no torch: nothing else to do
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            // If requested mode isn’t supported, fall back gracefully
            guard device.isTorchModeSupported(mode) else {
                device.torchMode = .off
                return
            }

            switch mode {
            case .on:
                // Use max available torch level if we can, else default ON
        
                let level = min(1.0, AVCaptureDevice.maxAvailableTorchLevel)
                    try? device.setTorchModeOn(level: level)

            case .auto:
                device.torchMode = .auto
            case .off:
                device.torchMode = .off
            @unknown default:
                device.torchMode = .off
            }

        } catch {
            print("Torch config error: \(error)")
        }
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
    func takePicture(path :String,flutterResult:  @escaping FlutterResult){
        self.imageSavePath = path;
        self.flutterResultTakePicture = flutterResult;
        let settings = AVCapturePhotoSettings()
        if captureDevice.hasFlash {
            settings.flashMode = self.flashMode
        }
        photoOutput?.capturePhoto(with: settings, delegate:self)
    }
    
    // Save to the provided path (or Documents/pic.jpg) and return the path via FlutterResult
    func saveImage(image: UIImage) -> Bool {
        guard let data = image.jpegData(compressionQuality: 0.95) ?? image.pngData() else {
            self.flutterResultTakePicture?(FlutterError(code: "-103a", message: "Could not encode image", details: nil))
            return false
        }
        let url: URL = {
            let dir = (try? FileManager.default.url(for: .documentDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil,
                                                    create: true))
                      ?? URL(fileURLWithPath: NSTemporaryDirectory())
            return dir.appendingPathComponent("pic.jpg")
        }()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            self.flutterResultTakePicture?(url.path)
            return true
        } catch {
            print("saveImage error: \(error)")
            self.flutterResultTakePicture?(FlutterError(code: "-103", message: error.localizedDescription, details: nil))
            return false
        }
    }

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
//    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        guard let tr = textRecognizer else { return }
//
//        let visionImage = VisionImage(buffer: sampleBuffer)
//        let base = imageOrientation(fromDevicePosition: cameraPosition)
//        visionImage.orientation = rotate(base, turns: forcedQuarterTurns)
//
//        do {
//            let result = try tr.results(in: visionImage)
//            let txt = result.text
//            if !txt.isEmpty {
//                var listLineModel: [LineModel] = []
//
//                for b in result.blocks {
//                    for l in b.lines {
//                        let lineModel : LineModel = LineModel()
//                        lineModel.text = l.text
//                        for c in l.cornerPoints {
//                            lineModel.cornerPoints.append(CornerPointModel(x: c.cgPointValue.x, y: c.cgPointValue.y))
//                        }
//                        listLineModel.append(lineModel)
//                    }
//                }
//
//                self.onTextRead(text: txt, values: listLineModel, path: "", orientation:  visionImage.orientation.rawValue)
//
//            } else {
//                self.onTextRead(text: "", values: [], path: "", orientation:  nil)
//            }
//
//        } catch {
//            print("can't fetch result: \(error)")
//        }
//    }

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
            visionImage.orientation = rotate(image!.imageOrientation, turns: forcedQuarterTurns)
            processImage(visionImage: visionImage, selectedImagePath: path)
        } catch {
            print("Error loading image : \(error)")
        }
    }

    func processImage(visionImage: VisionImage, image: UIImage? = nil, selectedImagePath : String? = nil) {
        if textRecognizer != nil {
            if let ui = image {
                visionImage.orientation = rotate(ui.imageOrientation, turns: forcedQuarterTurns)
            } else {
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
            let target = max(minZoomFactor, min(device.videoZoomFactor, maxZoomFactor))
            do {
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: target, withRate: 8.0)
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
        return UIApplication.shared.statusBarOrientation
    }

    private func currentUIOrientation() -> UIDeviceOrientation {
        let io = interfaceOrientation()
        switch io {
        case .portrait:             return .portrait
        case .portraitUpsideDown:   return .portraitUpsideDown
        case .landscapeLeft:        return .landscapeRight
        case .landscapeRight:       return .landscapeLeft
        default:                    return .portrait
        }
    }

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

    // ===== Macro helpers =====
    @available(iOS 13.0, *)
    private func setMacro(enabled: Bool) {
        isMacroEnabled = enabled
        applyFocusConfiguration()
        // Optional: small zoom to help framing when close
        
        if(enabled){
            switchBackCamera(preferUltraWide: enabled)
        }else{
            switchBackCamera(preferUltraWide: false)
        }
//        if enabled { setZoom(factor: max(1.0, min(1.3, maxZoomFactor)), animated: true) }
//        if !enabled { setZoom(factor: max(1.0, min(1.0, maxZoomFactor)), animated: true) }
    }

    private func applyFocusConfiguration() {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()

            // General AF settings
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            device.isSubjectAreaChangeMonitoringEnabled = true

            // Set center focus point for stability (0..1 coordinates)
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }

            // Macro bias
            if isMacroEnabled, device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            } else if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .none
            }

            // Use continuous AF, falling back to auto focus
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            } else if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }

            // (Optional) slight manual nudge toward near focus if supported
            // Uncomment if you want a stronger macro bias:
            // if isMacroEnabled, device.isFocusModeSupported(.locked) {
            //     let near: Float = 0.85 // 0.0 = far, 1.0 = near (approx)
            //     device.setFocusModeLocked(lensPosition: near) { _ in }
            // }
            channel.invokeMethod("onMacroChanged", arguments: self.buildMacroStatus())

            device.unlockForConfiguration()
        } catch {
            print("applyFocusConfiguration error: \(error)")
        }
    }
    
    private func buildMacroStatus() -> [String: Any] {
        print("buildMacroStatus")
        var status: [String: Any] = [
            "requestedMacro": isMacroEnabled as Any
        ]
        guard let d = captureDevice else { return status }

        status["supportsNearRestriction"] = d.isAutoFocusRangeRestrictionSupported
        if d.isAutoFocusRangeRestrictionSupported {
            status["autoFocusRangeRestriction"] = (d.autoFocusRangeRestriction == .near ? "near" :
                                                   d.autoFocusRangeRestriction == .far  ? "far"  : "none")
        }
        status["focusMode"] = {
            switch d.focusMode {
            case .locked: return "locked"
            case .autoFocus: return "autoFocus"
            case .continuousAutoFocus: return "continuousAutoFocus"
            @unknown default: return "unknown"
            }
        }()
        status["smoothAutoFocus"] = d.isSmoothAutoFocusSupported ? d.isSmoothAutoFocusEnabled : false
        status["subjectAreaMonitoring"] = d.isSubjectAreaChangeMonitoringEnabled
        status["focusPOISupported"] = d.isFocusPointOfInterestSupported
        if d.isFocusPointOfInterestSupported {
            status["focusPOI"] = ["x": d.focusPointOfInterest.x, "y": d.focusPointOfInterest.y]
        }
        status["zoomFactor"] = d.videoZoomFactor
        status["maxZoomFactor"] = d.activeFormat.videoMaxZoomFactor
        status["deviceType"] = d.deviceType.rawValue
        if #available(iOS 13.0, *) {
            status["fieldOfView"] = d.activeFormat.videoFieldOfView
        }
        // Lens position is read-only; useful to see we're near the close end (≈1.0)
        if d.isFocusModeSupported(.continuousAutoFocus) || d.isFocusModeSupported(.autoFocus) || d.isFocusModeSupported(.locked) {
            status["lensPosition"] = d.lensPosition  // 0 = far, 1 = near (approximate)
        }
        print(status)
        return status
    }
    
    /// Switches the active back camera device. If `preferUltraWide` is true,
    /// it picks Ultra Wide (for close focus). Otherwise it uses the virtual
    /// multi-camera if available (triple/dual-wide), falling back to Wide.
    @available(iOS 13.0, *)
    private func switchBackCamera(preferUltraWide: Bool) {
        guard cameraPosition == .back else { return }

        // Choose target device
        let target: AVCaptureDevice? = {
            if preferUltraWide {
                // Macro: Ultra Wide focuses closest (on supported iPhones)
                return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            } else {
                // Normal: prefer virtual multi-cam so iOS can pick best lens for zoom range
                return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            }
        }()

        guard let newDevice = target else { return }

        do {
            let newInput = try AVCaptureDeviceInput(device: newDevice)

            session.beginConfiguration()
            defer { session.commitConfiguration() }

            // Remove ONLY existing video device inputs
            for input in session.inputs {
                if let dInput = input as? AVCaptureDeviceInput, dInput.device.hasMediaType(.video) {
                    session.removeInput(dInput)
                }
            }

            if session.canAddInput(newInput) {
                session.addInput(newInput)
                self.captureDevice = newDevice
            }

            // Re-apply focus / macro bias on the new device
            applyFocusConfiguration()

            // Keep your existing outputs; they remain attached to the session
            // Preview layer will continue using the same session

        } catch {
            print("switchBackCamera error: \(error)")
        }
    }
    
    /// Map a point from image space (width x height) into previewView's coordinates,
    /// taking .resizeAspectFill into account. If `turns` != 0, rotates the image point
    /// by 90° * turns around the image center before mapping.
    private func previewPoint(fromImagePoint p: CGPoint,
                              imageSize: CGSize,
                              turns: Int = 0) -> CGPoint
    {
        var pt = p
        var imgW = imageSize.width
        var imgH = imageSize.height

        // Apply 90° steps rotation in image space if needed
        let t = ((turns % 4) + 4) % 4
        if t != 0 {
            // rotate about image center
            let cx = imgW * 0.5, cy = imgH * 0.5
            let x = p.x - cx, y = p.y - cy
            var xr = x, yr = y
            // 90° CW per turn
            for _ in 0..<t {
                let nx =  y
                let ny = -x
                xr = nx; yr = ny
                // swap width/height for each quarter-turn
                swap(&imgW, &imgH)
            }
            pt = CGPoint(x: xr + imgW*0.5, y: yr + imgH*0.5)
        }

        // Aspect-fill scale & offset to previewView
        let pv = previewView.bounds.size
        let s = max(pv.width / imgW, pv.height / imgH)
        let drawW = imgW * s
        let drawH = imgH * s
        let ox = (pv.width  - drawW) * 0.5
        let oy = (pv.height - drawH) * 0.5

        return CGPoint(x: ox + pt.x * s, y: oy + pt.y * s)
    }
    
    private func drawOverlays(for lines: [LineModel],
                              imageSize: CGSize,
                              turns: Int)
    {
        let path = UIBezierPath()

        for line in lines {
            guard line.cornerPoints.count >= 4 else { continue }

            let pts = line.cornerPoints.map { cp -> CGPoint in
                let ip = CGPoint(x: cp.x, y: cp.y)
                return self.previewPointUsingPreviewLayer(fromImagePoint: ip,
                                                          imageSize: imageSize,
                                                          turns: turns)
            }

            let quad = UIBezierPath()
            quad.move(to: pts[0])
            quad.addLine(to: pts[1])
            quad.addLine(to: pts[2])
            quad.addLine(to: pts[3])
            quad.close()
            path.append(quad)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(false)
        CATransaction.setAnimationDuration(0.12)
        overlayLayer.path = path.cgPath
        CATransaction.commit()
    }

    
    /// Convert an image-space pixel point (x in [0..imageW], y in [0..imageH])
    /// to a point in the previewView using previewLayer's converter.
    /// This handles .resizeAspectFill cropping, mirroring and orientation.
    private func previewPointUsingPreviewLayer(fromImagePoint p: CGPoint,
                                               imageSize: CGSize,
                                               turns: Int = 0) -> CGPoint
    {
        // Apply 90° CW rotations in image space if you use forcedQuarterTurns
        var pt = p
        var w = imageSize.width
        var h = imageSize.height
        let t = ((turns % 4) + 4) % 4
        if t != 0 {
            // rotate around image center by 90° CW per turn
            let cx = w * 0.5, cy = h * 0.5
            var x = p.x - cx, y = p.y - cy
            for _ in 0..<t {
                let nx =  y
                let ny = -x
                x = nx; y = ny
                swap(&w, &h) // width/height swap each quarter turn
            }
            pt = CGPoint(x: x + w*0.5, y: y + h*0.5)
        }

        // Normalize to [0,1] in the *capture device* space
        let norm = CGPoint(x: pt.x / w, y: pt.y / h)

        // Ask the preview layer to transform to layer space (handles aspectFill + mirroring)
        guard let pv = self.previewLayer else { return .zero }
        return pv.layerPointConverted(fromCaptureDevicePoint: norm)
    }

    
    private func clearOverlays() {
        CATransaction.begin()
        CATransaction.setDisableActions(false)
        CATransaction.setAnimationDuration(0.08)
        overlayLayer.path = nil
        CATransaction.commit()
    }
    
    public func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let tr = textRecognizer else { return }

        // get image size from the frame
        if let img = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let w = CGFloat(CVPixelBufferGetWidth(img))
            let h = CGFloat(CVPixelBufferGetHeight(img))
            lastFrameImageSize = CGSize(width: w, height: h)
        }

        let visionImage = VisionImage(buffer: sampleBuffer)
        let base = imageOrientation(fromDevicePosition: cameraPosition)
        visionImage.orientation = rotate(base, turns: forcedQuarterTurns)

        do {
            let result = try tr.results(in: visionImage)
            let txt = result.text

            var listLineModel: [LineModel] = []
            if !txt.isEmpty {
                for b in result.blocks {
                    for l in b.lines {
                        let lineModel = LineModel()
                        lineModel.text = l.text
                        for c in l.cornerPoints {
                            lineModel.cornerPoints.append(
                                CornerPointModel(x: c.cgPointValue.x, y: c.cgPointValue.y)
                            )
                        }
                        listLineModel.append(lineModel)
                    }
                }
            }

            // ----- draw overlays -----
            let imgSize = self.lastFrameImageSize
            DispatchQueue.main.async {
                if !txt.isEmpty && imgSize != .zero {
                    self.drawOverlays(for: listLineModel,
                                      imageSize: imgSize,
                                      turns: self.forcedQuarterTurns)
                } else {
                    self.clearOverlays()
                }
            }
            // -------------------------

            if !txt.isEmpty {
                self.onTextRead(text: txt, values: listLineModel, path: "", orientation: visionImage.orientation.rawValue)
            } else {
                self.onTextRead(text: "", values: [], path: "", orientation: nil)
            }

        } catch {
            print("can't fetch result: \(error)")
        }
    }






}
