import Flutter
import UIKit
import Foundation
import AVFoundation
import MLKitTextRecognition
import MLKitVision

class CameraKitOcrPlusView: NSObject, FlutterPlatformView, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var _view: UIView
    var captureSession = AVCaptureSession()
    var captureDevice: AVCaptureDevice!
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var channel: FlutterMethodChannel?
    var initCameraFinished: Bool! = false
    var cameraID = 0
    var textRecognizer: TextRecognizer

    init(frame: CGRect, messenger: FlutterBinaryMessenger) {
        _view = UIView(frame: frame)
        _view.backgroundColor = UIColor.black
        textRecognizer = TextRecognizer.textRecognizer() // Initialize the text recognizer
        super.init()
        setupAVCapture()
        setupCamera()
        channel = FlutterMethodChannel(name: "camera_kit_plus", binaryMessenger: messenger)
        channel?.setMethodCallHandler(handle)
    }
    
    private func createNativeView() {
        let screenSize = UIScreen.main.bounds
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = UIColor.blue
        label.frame = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
        label.autoresizingMask = [.flexibleWidth, .flexibleTopMargin, .flexibleBottomMargin]
        label.center = _view.center // Center the label within _view
        label.textColor = UIColor.blue
        _view.addSubview(label)

    }

    func view() -> UIView {
        return _view
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments
        let myArgs = args as? [String: Any]
        switch call.method {
        case "getCameraPermission":
            break
        case "initCamera":
            break
        case "switchCamera":
            let cameraID = (myArgs?["cameraID"] as! Int)
            self.switchCamera(cameraID: cameraID, result: result)
            break
        case "pauseCamera":
            self.pauseCamera(result: result)
            break
        case "resumeCamera":
            self.resumeCamera(result: result)
            break
        default:
            result(false)
        }
    }

    func setupAVCapture() {
        captureSession.sessionPreset = AVCaptureSession.Preset.high
        captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private func setupCamera() {
        print("Setting up the camera...")
        
        // Initialize the capture device
        captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        if captureDevice == nil {
            print("Error: captureDevice is nil.")
            return
        }
        print("captureDevice initialized: \(captureDevice!)")
        
        // Configure camera input
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: captureDevice)
        } catch {
            print("Failed to set up camera input: \(error)")
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            print("Could not add video input to session")
            return
        }

        // Configure video output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            print("Could not add video output to session")
            return
        }

        // Set up the preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = _view.bounds
        previewLayer?.connection?.videoOrientation = .portrait // Set orientation explicitly
        
        startSession(isFirst: true)
    }
    
    func startSession(isFirst: Bool) {
        DispatchQueue.main.async {
            let rootLayer :CALayer = self._view.layer
            rootLayer.masksToBounds = true
            if(rootLayer.bounds.size.width != 0 && rootLayer.bounds.size.width != 0){
                self._view.frame = rootLayer.bounds
                let previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.frame = self._view.bounds
                previewLayer.connection?.videoOrientation = .portrait // Set orientation explicitly
                self._view.layer.addSublayer(previewLayer)
                self.captureSession.startRunning()
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    self.startSession(isFirst: isFirst)
                }
            }
        }
    }



    func switchCamera(cameraID: Int, result: @escaping FlutterResult) {
        captureSession.stopRunning()
        self.cameraID = cameraID
        captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraID == 0 ? .back : .front)
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
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = imageOrientation()

        textRecognizer.process(visionImage) { result, error in
            guard error == nil, let result = result else {
                print("Error recognizing text: \(String(describing: error))")
                return
            }
            
            if(result.text != "") {
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
                
                
                self.onTextRead(text: result.text, values: listLineModel, path: "", orientation:  visionImage.orientation.rawValue)
                
            } else {
                
                self.onTextRead(text: "", values: [], path: "", orientation:  nil)
            }
//            print(result.text)
//            let recognizedText = result.text
//            self.channel?.invokeMethod("onTextRead", arguments: recognizedText)
        }
    }

    private func imageOrientation() -> UIImage.Orientation {
        switch UIDevice.current.orientation {
        case .portrait:
            return .right
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        case .portraitUpsideDown:
            return .left
        default:
            return .right
        }
    }

    func dispose() {
        captureSession.stopRunning()
    }
    
    
    func onTextRead(text: String, values: [LineModel], path: String?, orientation: Int?) {
        let data = OcrData(text: text, path: path, orientation: orientation, lines: values)
        let jsonEncoder = JSONEncoder()
        let jsonData = try! jsonEncoder.encode(data)
        let json = String(data: jsonData, encoding: String.Encoding.utf8)
        self.channel?.invokeMethod("onTextRead", arguments: json)
    }
    
//    func textRead(text: String, values: [LineModel], path: String?, orientation: Int?) {
//        
//        
//        let data = OcrData(text: text, path: path, orientation: orientation, lines: values)
//        let jsonEncoder = JSONEncoder()
//        let jsonData = try! jsonEncoder.encode(data)
//        let json = String(data: jsonData, encoding: String.Encoding.utf8)
//        flutterResultOcr(json)
//    }
}


struct OcrData: Codable {
    var text: String?
    var path: String?
    var orientation: Int?
    var lines: [LineModel]=[]
}

// Encode


class LineModel: Codable {
    var text:String = ""
    var cornerPoints : [CornerPointModel] = []
}


class CornerPointModel: Codable {
    
    init(x:CGFloat, y:CGFloat) {
        self.x = x
        self.y = y
    }
    
    var x:CGFloat
    var y:CGFloat
}
