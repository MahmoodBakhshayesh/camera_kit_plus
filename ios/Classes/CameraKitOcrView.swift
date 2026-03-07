import Flutter
import UIKit

import Foundation
import AVFoundation
import AudioToolbox
import MLKitTextRecognition
import MLKitCommon
import MLKitVision

class CameraOcrViewContainer: UIView {
    var onLayoutSubviews: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }
}

@available(iOS 13.0, *)
class CameraKitOcrView: NSObject, FlutterPlatformView, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var _view: UIView
    var channel: FlutterMethodChannel
    let frame: CGRect
    var imageSavePath:String!
    var isCameraVisible:Bool! = true
    var initCameraFinished:Bool! = false
    var isFillScale:Bool!
    var flashMode:AVCaptureDevice.FlashMode!
    var cameraPosition: AVCaptureDevice.Position! = .back
    var previewView : CameraOcrViewContainer!
    var videoDataOutput: AVCaptureVideoDataOutput!
    var videoDataOutputQueue: DispatchQueue!
    var photoOutput: AVCapturePhotoOutput?
    var previewLayer:AVCaptureVideoPreviewLayer!
    var captureDevice : AVCaptureDevice!
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera_kit_plus.ocr.sessionQueue")
    
    var textRecognizer : TextRecognizer?
    var flutterResultTakePicture:FlutterResult!
    var flutterResultOcr:FlutterResult!
    var orientation : UIImage.Orientation!
    private var isCapturing = false
    private var overlayView: UIView!
    private let overlayLayer = CAShapeLayer()
    private var lastFrameImageSize: CGSize = .zero
    private var muteShutter: Bool = true
    private var prevAudioCategory: AVAudioSession.Category?
    private var prevAudioMode: AVAudioSession.Mode?
    private var prevAudioOptions: AVAudioSession.CategoryOptions = []
    private var didChangeAudioSession = false
    var showTextRectangles: Bool = false
    private var focusRequired: Bool = false


    /// 0:camera 1:barcodeScanner 2:ocrReader
    var usageMode:Int = 0

    // Zoom
    private var minZoomFactor: CGFloat = 1.0
    private var lastZoomFactor: CGFloat = 1.0
    private var maxZoomFactor: CGFloat {
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
        self.flashMode = .off
        
        if let myArgs = args as? [String: Any] {
            self.showTextRectangles = myArgs["showTextRectangles"] as? Bool ?? false
            self.focusRequired = myArgs["focusRequired"] as? Bool ?? false // Default to false for OCR
        }

        self.channel.setMethodCallHandler(handle)
        createNativeView(view: _view)
        setupCamera()
        channel = FlutterMethodChannel(name: "camera_kit_plus", binaryMessenger: messenger!)
        channel.setMethodCallHandler(handle)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleOrientationChange),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func view() -> UIView {
        if previewView == nil {
            self.previewView = CameraOcrViewContainer(frame: frame)
            self.previewView.onLayoutSubviews = { [weak self] in
                self?.updatePreviewLayout()
            }
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
    
    private func updatePreviewLayout() {
        guard let pl = previewLayer else { return }
        pl.frame = previewView.bounds
        updateVideoOrientation()
        layoutOverlaysToPreviewBounds()
    }

    private func updateVideoOrientation() {
        guard let conn = previewLayer?.connection, conn.isVideoOrientationSupported else { return }
        switch interfaceOrientation() {
        case .landscapeLeft:
            conn.videoOrientation = .landscapeLeft
        case .landscapeRight:
            conn.videoOrientation = .landscapeRight
        case .portraitUpsideDown:
            conn.videoOrientation = .portraitUpsideDown
        default:
            conn.videoOrientation = .portrait
        }
    }
    
    @objc private func handleOrientationChange() {
        DispatchQueue.main.async {
            self.updatePreviewLayout()
        }
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
        case "changeFlashMode":
            let mode = (myArgs?["flashModeID"] as? Int)!
            changeFlashMode(modeID: mode, result: result)
            result(true)
        case "pauseCamera":
            self.pauseCamera(); result(true)
        case "resumeCamera":
            self.resumeCamera(); result(true)
        case "takePicture":
            let path = (myArgs?["path"] as? String)!
            self.takePicture(path:path,flutterResult: result)
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
        case "setMacro":
            let enabled = (myArgs?["enabled"] as? Bool) ?? false
            self.setMacro(enabled: enabled)
            result(true)
        case "dispose":
            result(true)
        default:
            result(false)
        }
    }

    func getCameraPermission(flutterResult:  @escaping FlutterResult) {
        if AVCaptureDevice.authorizationStatus(for: .video) ==  .authorized {
            flutterResult(true as Bool)
        } else {
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { (granted: Bool) in
                flutterResult(granted)
            })
        }
    }

    func setupCamera(){
        self.isFillScale = true
        self.cameraPosition = .back
        self.flashMode = .off
        textRecognizer = TextRecognizer.textRecognizer()
        self.setupAVCapture()
    }

    @available(iOS 13.0, *)
    private func bestBackCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        return discovery.devices.first
    }

    @available(iOS 13.0, *)
    func setupAVCapture(){
        session.sessionPreset = .hd1920x1080
        if cameraPosition == .back, let dev = bestBackCamera() {
            captureDevice = dev
        } else if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) {
            captureDevice = dev
        } else {
            return
        }
        beginSession()
    }

    func beginSession(isFirst: Bool = true){
        do {
            let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
            if self.session.canAddInput(deviceInput){
                self.session.addInput(deviceInput)
            }
            lastZoomFactor = 1.0

            videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue")
            videoDataOutput.setSampleBufferDelegate(self, queue:self.videoDataOutputQueue)
            if session.canAddOutput(videoDataOutput!){
                session.addOutput(videoDataOutput)
            }

            photoOutput = AVCapturePhotoOutput()
            if session.canAddOutput(photoOutput!){
                session.addOutput(photoOutput!)
            }
            applyFocusConfiguration()
            previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
            previewLayer.videoGravity = .resizeAspectFill
            startSession(isFirst: isFirst)
        } catch let error as NSError {
            print("error: \(error.localizedDescription)")
        }
    }

    func startSession(isFirst: Bool) {
        DispatchQueue.main.async {
            if self.previewView == nil { _ = self.view() }
            let rootLayer :CALayer = self.previewView.layer
            rootLayer.masksToBounds = true
            
            if(rootLayer.bounds.size.width > 0){
                self.previewLayer.frame = rootLayer.bounds
                self.updateVideoOrientation()
                self.layoutOverlaysToPreviewBounds()
                if self.previewLayer.superlayer == nil {
                    rootLayer.addSublayer(self.previewLayer)
                    if self.overlayView != nil {
                        self.previewView.bringSubviewToFront(self.overlayView)
                    }
                }
                self.sessionQueue.async {
                    if !self.session.isRunning { self.session.startRunning() }
                }
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    self.startSession(isFirst: isFirst)
                }
            }
        }
    }

    func setFlashMode(mode: AVCaptureDevice.TorchMode) {
        guard let device = self.captureDevice, device.hasTorch, self.cameraPosition == .back else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.torchMode = device.isTorchModeSupported(mode) ? mode : .off
        } catch {
            print("Torch config error: \(error)")
        }
    }

    func changeFlashMode(modeID: Int,result:  @escaping FlutterResult){
        setFlashMode(mode: (modeID == 1 ? .on : .off))
        result(true)
    }

    func pauseCamera() {
        stopCamera()
    }

    func resumeCamera() {
        sessionQueue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stopCamera(){
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func takePicture(path :String, flutterResult:  @escaping FlutterResult){
        guard let photoOutput = self.photoOutput, !isCapturing else { return }
        isCapturing = true
        self.flutterResultTakePicture = flutterResult
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { isCapturing = false }
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            self.flutterResultTakePicture?(FlutterError(code: "-102", message: "No photo data", details: nil))
            return
        }
        saveImage(image: image)
    }
    
    func saveImage(image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            self.flutterResultTakePicture?(FlutterError(code: "-103a", message: "Could not encode image", details: nil))
            return
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pic.jpg")
        do {
            try data.write(to: url, options: .atomic)
            self.flutterResultTakePicture?(url.path)
        } catch {
            self.flutterResultTakePicture?(FlutterError(code: "-103", message: error.localizedDescription, details: nil))
        }
    }

    func onTextRead(text: String, values: [LineModel], path: String?, orientation: Int?) {
        let data = OcrData(text: text, path: path, orientation: orientation, lines: values)
        if let json = try? JSONEncoder().encode(data), let jsonString = String(data: json, encoding: .utf8) {
            channel.invokeMethod("onTextRead", arguments: jsonString)
        }
    }
    
    private func attachZoomGesturesIfNeeded() {
        if previewView.gestureRecognizers?.isEmpty == false { return }
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        previewView.addGestureRecognizer(pinch)
    }

    @objc private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        guard let device = self.captureDevice else { return }
        if pinch.state == .began { lastZoomFactor = device.videoZoomFactor }
        var newFactor = lastZoomFactor * pinch.scale
        newFactor = max(minZoomFactor, min(newFactor, maxZoomFactor))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = newFactor
            device.unlockForConfiguration()
        } catch { print("Zoom lock error: \(error)") }
    }

    private func setZoom(factor: CGFloat, animated: Bool = true) {
        guard let device = self.captureDevice else { return }
        let clamped = max(minZoomFactor, min(factor, maxZoomFactor))
        do {
            try device.lockForConfiguration()
            if animated { device.ramp(toVideoZoomFactor: clamped, withRate: 8.0) } else { device.videoZoomFactor = clamped }
            channel.invokeMethod("onZoomChanged", arguments: factor)
            device.unlockForConfiguration()
            lastZoomFactor = clamped
        } catch { print("setZoom error: \(error)") }
    }
    
    private func interfaceOrientation() -> UIInterfaceOrientation {
        return UIApplication.shared.windows.first?.windowScene?.interfaceOrientation ?? .portrait
    }

    private func imageOrientation(fromDevicePosition devicePosition: AVCaptureDevice.Position = .back) -> UIImage.Orientation {
        switch interfaceOrientation() {
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        case .portraitUpsideDown: return .left
        default: return .right
        }
    }

    @available(iOS 13.0, *)
    private func setMacro(enabled: Bool) {
        isMacroEnabled = enabled
        applyFocusConfiguration()
        switchBackCamera(preferUltraWide: enabled)
    }

    private func applyFocusConfiguration() {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if focusRequired {
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            } else {
                if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
            }
            if isMacroEnabled && device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            } else if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .none
            }
            channel.invokeMethod("onMacroChanged", arguments: self.buildMacroStatus())
        } catch {
            print("applyFocusConfiguration error: \(error)")
        }
    }
    
    private func buildMacroStatus() -> [String: Any] {
        guard let d = captureDevice else { return [:] }
        return ["requestedMacro": isMacroEnabled, "focusMode": d.focusMode.rawValue]
    }
    
    @available(iOS 13.0, *)
    private func switchBackCamera(preferUltraWide: Bool) {
        guard cameraPosition == .back else { return }
        let targetType: AVCaptureDevice.DeviceType = preferUltraWide ? .builtInUltraWideCamera : .builtInWideAngleCamera
        guard let newDevice = AVCaptureDevice.default(targetType, for: .video, position: .back) else { return }
        do {
            let newInput = try AVCaptureDeviceInput(device: newDevice)
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                self.captureDevice = newDevice
            }
            session.commitConfiguration()
            applyFocusConfiguration()
        } catch {
            print("switchBackCamera error: \(error)")
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let tr = textRecognizer, let img = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = imageOrientation()
        
        do {
            let result = try tr.results(in: visionImage)
            if !result.text.isEmpty {
                onTextRead(text: result.text, values: result.blocks.flatMap { $0.lines }.map { LineModel(text: $0.text, cornerPoints: $0.cornerPoints.map { CornerPointModel(point: $0.cgPointValue) }) }, path: nil, orientation: visionImage.orientation.rawValue)
            }
        } catch {
            print("can't fetch result: \(error)")
        }
    }
}
