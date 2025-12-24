import Flutter
import UIKit
import Foundation
import AVFoundation
import MLKitTextRecognition
import MLKitVision

final class CameraKitOcrPlusView: NSObject, FlutterPlatformView, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Flutter / UI
    private let _view: UIView
    private var channel: FlutterMethodChannel?

    // MARK: - Camera
    private let captureSession = AVCaptureSession()
    private var captureDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - State
    var initCameraFinished: Bool! = false
    var cameraID = 0 // 0 back, 1 front

    // MARK: - MLKit
    var textRecognizer: TextRecognizer

    // MARK: - Zoom
    private var minZoomFactor: CGFloat = 1.0
    private var lastZoomFactor: CGFloat = 1.0
    private var maxZoomFactor: CGFloat {
        return min(self.captureDevice?.activeFormat.videoMaxZoomFactor ?? 1.0, 8.0)
    }

    // MARK: - Init
    init(frame: CGRect, messenger: FlutterBinaryMessenger) {
        _view = UIView(frame: frame)
        _view.backgroundColor = .black
        _view.isUserInteractionEnabled = true

        textRecognizer = TextRecognizer.textRecognizer()

        super.init()

        attachZoomGesturesIfNeeded()

        channel = FlutterMethodChannel(name: "camera_kit_plus", binaryMessenger: messenger)
        channel?.setMethodCallHandler(handle)

        setupAVCapture()
        setupCamera(cameraID: 0)
        startSession()
        startOrientationObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func view() -> UIView { _view }

    // MARK: - Flutter channel
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {
        case "getCameraPermission":
            requestCameraPermission(result: result)

        case "initCamera":
            // kept for compatibility
            result(true)

        case "switchCamera":
            let id = (args?["cameraID"] as? Int) ?? 0
            switchCamera(cameraID: id, result: result)

        case "pauseCamera":
            pauseCamera(result: result)

        case "resumeCamera":
            resumeCamera(result: result)

        case "setZoom":
            if let z = args?["zoom"] as? Double {
                setZoom(factor: CGFloat(z), animated: true)
                result(true)
            } else {
                result(FlutterError(code: "bad_args", message: "zoom (double) is required", details: nil))
            }

        case "resetZoom":
            setZoom(factor: 1.0, animated: true)
            result(true)

        default:
            result(false)
        }
    }

    func requestCameraPermission(result: @escaping FlutterResult) {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
            result(true)
        } else {
            result(false)
        }
    }

    // MARK: - AVCapture setup
    private func setupAVCapture() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        captureSession.commitConfiguration()

        // output config once
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
    }

    private func setupCamera(cameraID: Int) {
        self.cameraID = cameraID
        lastZoomFactor = 1.0

        captureSession.beginConfiguration()

        // Remove previous input
        if let input = videoInput {
            captureSession.removeInput(input)
            videoInput = nil
        }

        // Remove previous output (we will add again safely)
        if captureSession.outputs.contains(videoOutput) {
            captureSession.removeOutput(videoOutput)
        }

        let position: AVCaptureDevice.Position = (cameraID == 0) ? .back : .front
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        captureDevice = device

        guard let captureDevice else {
            print("Error: captureDevice is nil.")
            captureSession.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                videoInput = input
            } else {
                print("Could not add video input to session")
            }
        } catch {
            print("Failed to create AVCaptureDeviceInput: \(error)")
        }

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            print("Could not add video output to session")
        }

        // ✅ Preview layer should be created once and kept
        if previewLayer == nil {
            let pl = AVCaptureVideoPreviewLayer(session: captureSession)
            pl.videoGravity = .resizeAspectFill
            pl.frame = _view.bounds
            _view.layer.masksToBounds = true
            _view.layer.addSublayer(pl)
            previewLayer = pl
        } else {
            previewLayer?.session = captureSession
            previewLayer?.frame = _view.bounds
        }

        captureSession.commitConfiguration()

        // Apply correct orientation immediately
        DispatchQueue.main.async { [weak self] in
            self?.updateConnectionsOrientation()
        }
    }

    private func startSession() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
            self.layoutPreviewToBounds()
            self.updateConnectionsOrientation()
        }
    }

    func pauseCamera(result: @escaping FlutterResult) {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        result(true)
    }

    func resumeCamera(result: @escaping FlutterResult) {
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
        DispatchQueue.main.async { [weak self] in
            self?.updateConnectionsOrientation()
        }
        result(true)
    }

    func dispose() {
        stopOrientationObservers()
        if captureSession.isRunning { captureSession.stopRunning() }
    }

    func switchCamera(cameraID: Int, result: @escaping FlutterResult) {
        if captureSession.isRunning { captureSession.stopRunning() }
        setupCamera(cameraID: cameraID)
        startSession()
        result(true)
    }

    // MARK: - Rotation / Orientation (FIX)
    private func startOrientationObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onDeviceOrientationChanged),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onAppDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }

    private func stopOrientationObservers() {
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func onDeviceOrientationChanged() {
        // When user unlocks rotation, device orientation changes,
        // but your Flutter UI may stay landscape. We must follow **interface orientation**
        DispatchQueue.main.async { [weak self] in
            self?.layoutPreviewToBounds()
            self?.updateConnectionsOrientation()
        }
    }

    @objc private func onAppDidBecomeActive() {
        DispatchQueue.main.async { [weak self] in
            self?.layoutPreviewToBounds()
            self?.updateConnectionsOrientation()
        }
    }

    private func layoutPreviewToBounds() {
        previewLayer?.frame = _view.bounds
    }

    /// Use the *current interface orientation* (windowScene) to drive preview + output orientation.
    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return scene.interfaceOrientation
        }
        // fallback
        return .portrait
    }

    private func avVideoOrientation(from io: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        // Mapping is not 1:1 (camera coordinates vs interface), but this is the standard mapping for preview/output.
        switch io {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portrait
        }
    }

    /// Apply same orientation to preview + video output connection.
    private func updateConnectionsOrientation() {
        let io = currentInterfaceOrientation()
        let vo = avVideoOrientation(from: io)

        // Preview
        if let c = previewLayer?.connection, c.isVideoOrientationSupported {
            c.videoOrientation = vo
        }

        // Output
        if let c = videoOutput.connection(with: .video), c.isVideoOrientationSupported {
            c.videoOrientation = vo
        }

        // If using front camera, you may want mirrored preview
        if let c = previewLayer?.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = (cameraID == 1)
        }
        if let c = videoOutput.connection(with: .video), c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = (cameraID == 1)
        }
    }

    // MARK: - MLKit orientation (FIX)
    /// MLKit VisionImage orientation must match how the pixels should be interpreted.
    /// Use **interface orientation** (not UIDevice orientation), otherwise iPad unlocked rotation breaks scanning.
    private func visionImageOrientation() -> UIImage.Orientation {
        let io = currentInterfaceOrientation()
        let isFront = (cameraID == 1)

        // These mappings are the commonly used MLKit mappings for AVCapture buffers.
        // Front camera needs mirrored variants.
        switch io {
        case .portrait:
            return isFront ? .leftMirrored : .right
        case .portraitUpsideDown:
            return isFront ? .rightMirrored : .left
        case .landscapeLeft:
            // home button/right side (depends device) — using interface orientation is the key
            return isFront ? .downMirrored : .up
        case .landscapeRight:
            return isFront ? .upMirrored : .down
        default:
            return isFront ? .leftMirrored : .right
        }
    }

    // MARK: - SampleBuffer delegate
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        // Create VisionImage from sampleBuffer
        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = visionImageOrientation()

        textRecognizer.process(visionImage) { [weak self] result, error in
            guard let self else { return }

            guard error == nil, let result = result else {
                // keep silent in production; but keep your debug
                // print("Error recognizing text: \(String(describing: error))")
                self.onTextRead(text: "", values: [], path: "", orientation: nil)
                return
            }

            if result.text.isEmpty {
                self.onTextRead(text: "", values: [], path: "", orientation: nil)
                return
            }

            var listLineModel: [LineModel] = []
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

            self.onTextRead(
                text: result.text,
                values: listLineModel,
                path: "",
                orientation: visionImage.orientation.rawValue
            )
        }
    }

    // MARK: - Zoom gestures (unchanged functionality)
    private func attachZoomGesturesIfNeeded() {
        guard _view.gestureRecognizers?.isEmpty ?? true else { return }

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        _view.addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTapResetZoom))
        doubleTap.numberOfTapsRequired = 2
        _view.addGestureRecognizer(doubleTap)
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
                print("Zoom end lock error: \(error)")
            }
            lastZoomFactor = target

        default:
            break
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

            DispatchQueue.main.async { [weak self] in
                self?.channel?.invokeMethod("onZoomChanged", arguments: factor)
            }

        } catch {
            print("setZoom error: \(error)")
        }
    }

    // MARK: - Send results to Flutter
    func onTextRead(text: String, values: [LineModel], path: String?, orientation: Int?) {
        let data = OcrData(text: text, path: path, orientation: orientation, lines: values)
        let jsonEncoder = JSONEncoder()
        let jsonData = try! jsonEncoder.encode(data)
        let json = String(data: jsonData, encoding: .utf8)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.channel?.invokeMethod("onTextRead", arguments: json)
        }
    }
}

// MARK: - Models (unchanged)
struct OcrData: Codable {
    var text: String?
    var path: String?
    var orientation: Int?
    var lines: [LineModel] = []
}

final class LineModel: Codable {
    var text: String = ""
    var cornerPoints: [CornerPointModel] = []
}

final class CornerPointModel: Codable {
    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
    var x: CGFloat
    var y: CGFloat
}
