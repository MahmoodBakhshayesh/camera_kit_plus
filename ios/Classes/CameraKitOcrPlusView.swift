import Flutter
import UIKit
import Foundation
import AVFoundation
import MLKitTextRecognition
import MLKitVision

class CameraOcrContainerView: UIView {
    var onLayoutSubviews: (() -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        onVisibilityChanged?(window != nil)
    }
}

class CameraKitOcrPlusView: NSObject, FlutterPlatformView, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var _view: CameraOcrContainerView
    var captureSession = AVCaptureSession()
    var captureDevice: AVCaptureDevice!
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var channel: FlutterMethodChannel?
    var initCameraFinished: Bool! = false
    var cameraID = 0
    var textRecognizer: TextRecognizer
    
    private var minZoomFactor: CGFloat = 1.0
    private var lastZoomFactor: CGFloat = 1.0
    private var maxZoomFactor: CGFloat {
        return min(self.captureDevice?.activeFormat.videoMaxZoomFactor ?? 1.0, 8.0)
    }

    init(frame: CGRect, messenger: FlutterBinaryMessenger) {
        _view = CameraOcrContainerView(frame: frame)
        _view.backgroundColor = UIColor.black
        _view.isUserInteractionEnabled = true
        
        textRecognizer = TextRecognizer.textRecognizer()
        super.init()
        
        _view.onLayoutSubviews = { [weak self] in
            self?.ensurePreviewLayer()
        }
        
        _view.onVisibilityChanged = { [weak self] isVisible in
            if isVisible {
                self?.resumeCamera(result: {_ in })
            } else {
                self?.pauseCamera(result: {_ in })
            }
        }
        
        attachZoomGesturesIfNeeded()
        setupAVCapture()
        setupCamera()
        channel = FlutterMethodChannel(name: "camera_kit_plus", binaryMessenger: messenger)
        channel?.setMethodCallHandler(handle)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleOrientationChange),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func view() -> UIView {
        return _view
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments
        let myArgs = args as? [String: Any]
        switch call.method {
        case "getCameraPermission":
            self.requestCameraPermission(result: result)
        case "switchCamera":
            let cameraID = (myArgs?["cameraID"] as! Int)
            self.switchCamera(cameraID: cameraID, result: result)
        case "pauseCamera":
            self.pauseCamera(result: result)
        case "resumeCamera":
            self.resumeCamera(result: result)
        case "setZoom":
              if let z = myArgs?["zoom"] as? Double {
                  self.setZoom(factor: CGFloat(z), animated: true)
                  result(true)
              } else {
                  result(FlutterError(code: "bad_args", message: "zoom (double) is required", details: nil))
              }
        case "resetZoom":
              self.setZoom(factor: 1.0, animated: true)
              result(true)
        default:
            result(false)
        }
    }

    func requestCameraPermission(result:  @escaping FlutterResult) {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
            result(true)
        }
    }

    func setupAVCapture() {
        captureSession.sessionPreset = .high
        captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private func setupCamera() {
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Error: captureDevice is nil.")
            return
        }
        self.captureDevice = captureDevice
        lastZoomFactor = 1.0

        do {
            let videoInput = try AVCaptureDeviceInput(device: captureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                print("Could not add video input to session")
                return
            }
        } catch {
            print("Failed to set up camera input: \(error)")
            return
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            print("Could not add video output to session")
            return
        }

        ensurePreviewLayer()
        startSession()
    }

    func startSession() {
        DispatchQueue.main.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }
    
    private func ensurePreviewLayer() {
        if previewLayer == nil {
            let pl = AVCaptureVideoPreviewLayer(session: self.captureSession)
            pl.videoGravity = .resizeAspectFill
            pl.frame = self._view.bounds
            self._view.layer.addSublayer(pl)
            self.previewLayer = pl
        } else {
            previewLayer?.frame = self._view.bounds
        }
        updateVideoOrientation()
    }

    private func updateVideoOrientation() {
        guard let conn = previewLayer?.connection, conn.isVideoOrientationSupported else { return }
        switch UIDevice.current.orientation {
        case .landscapeLeft:  conn.videoOrientation = .landscapeRight
        case .landscapeRight: conn.videoOrientation = .landscapeLeft
        case .portraitUpsideDown: conn.videoOrientation = .portraitUpsideDown
        default: conn.videoOrientation = .portrait
        }
    }
    
    @objc private func handleOrientationChange() {
        DispatchQueue.main.async {
            self.updateVideoOrientation()
            self.ensurePreviewLayer()
        }
    }

    func switchCamera(cameraID: Int, result: @escaping FlutterResult) {
        captureSession.stopRunning()
        self.cameraID = cameraID
        for input in captureSession.inputs { captureSession.removeInput(input) }
        for output in captureSession.outputs { captureSession.removeOutput(output) }
        setupCamera()
        result(true)
    }

    func pauseCamera(result: @escaping FlutterResult) {
        captureSession.stopRunning()
        result(true)
    }

    func resumeCamera(result: @escaping FlutterResult) {
        captureSession.startRunning()
        result(true)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = imageOrientation()

        textRecognizer.process(visionImage) { result, error in
            guard error == nil, let result = result, !result.text.isEmpty else { return }
            
            let lines = result.blocks.flatMap { $0.lines }.map {
                LineModel(text: $0.text, cornerPoints: $0.cornerPoints.map { CornerPointModel(point: $0.cgPointValue) })
            }
            self.onTextRead(text: result.text, values: lines, path: nil, orientation: visionImage.orientation.rawValue)
        }
    }

    private func imageOrientation() -> UIImage.Orientation {
        switch UIDevice.current.orientation {
        case .portrait: return .right
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        case .portraitUpsideDown: return .left
        default: return .right
        }
    }

    func dispose() {
        captureSession.stopRunning()
    }

    func onTextRead(text: String, values: [LineModel], path: String?, orientation: Int?) {
        let data = OcrData(text: text, path: path, orientation: orientation, lines: values)
        guard let json = try? JSONEncoder().encode(data), let jsonString = String(data: json, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            self.channel?.invokeMethod("onTextRead", arguments: jsonString)
        }
    }

    private func attachZoomGesturesIfNeeded() {
        guard _view.gestureRecognizers?.isEmpty ?? true else { return }
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        _view.addGestureRecognizer(pinch)
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
            device.unlockForConfiguration()
            lastZoomFactor = clamped
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onZoomChanged", arguments: factor)
            }
        } catch { print("setZoom error: \(error)") }
    }
}

struct OcrData: Codable {
    var text: String
    var path: String?
    var orientation: Int?
    var lines: [LineModel]
}

struct LineModel: Codable {
    var text: String
    var cornerPoints: [CornerPointModel]
}
