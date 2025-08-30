import Flutter
import UIKit


import Foundation
import AVFoundation
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
    
    /// 0:camera 1:barcodeScanner 2:ocrReader
    var usageMode:Int = 0
    private var minZoomFactor: CGFloat = 1.0
    private var lastZoomFactor: CGFloat = 1.0
    private var maxZoomFactor: CGFloat {
        // Cap practical zoom to 8x to avoid ugly noise; raise if you want
        return min(self.captureDevice?.activeFormat.videoMaxZoomFactor ?? 1.0, 8.0)
    }
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
            //            previewView.contentMode = UIView.ContentMode.scaleAspectFill
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
            break
        case "initCamera":
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
//                let initFlashModeID = (myArgs?["initFlashModeID"] as! Int);
//                let modeID = (myArgs?["modeID"] as! Int);
//                let fill = (myArgs?["fill"] as! Bool);
//                let barcodeTypeID = (myArgs?["barcodeTypeID"] as! Int);
//                let cameraTypeID = (myArgs?["cameraTypeID"] as! Int);
//                
//                self.initCamera( flashMode: initFlashModeID, fill: fill, barcodeTypeID: barcodeTypeID, cameraID: cameraTypeID,modeID: modeID)
//                
//            }
            break
        case "changeFlashMode":
            let flashModeID = (myArgs?["flashModeID"] as! Int);
//            self.setFlashMode(flashMode: flashModeID)
//            self.changeFlashMode()
            break
        case "changeCameraVisibility":
            let visibility = (myArgs?["visibility"] as! Bool)
            self.changeCameraVisibility(visibility: visibility)
            break
        case "pauseCamera":
            self.pauseCamera();
            break
        case "resumeCamera":
            self.resumeCamera()
            break
        case "takePicture":
            let path = (myArgs?["path"] as! String);
            self.takePicture(path:path,flutterResult: result)
            break
        case "dispose":
            self.getCameraPermission(flutterResult: result)
            break
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
                    if granted {
                        flutterResult(true as Bool)
                    } else {
                        flutterResult(false as Bool)
                    }
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
        var myBarcodeMode: Int
//        setFlashMode(flashMode: flashMode)
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
//        changeFlashMode()
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

            
            orientation = imageOrientation(
                fromDevicePosition: cameraPosition
            )
            
            if(usageMode == 1){
                videoDataOutput = AVCaptureVideoDataOutput()
                videoDataOutput.alwaysDiscardsLateVideoFrames=true
                
                videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue")
                videoDataOutput.setSampleBufferDelegate(self, queue:self.videoDataOutputQueue)
                if session.canAddOutput(videoDataOutput!){
                    session.addOutput(videoDataOutput!)
                }
                videoDataOutput.connection(with: .video)?.isEnabled = true
                
            }else if(usageMode == 2){
                videoDataOutput = AVCaptureVideoDataOutput()
                videoDataOutput.alwaysDiscardsLateVideoFrames = true
                
                videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue")
                videoDataOutput.setSampleBufferDelegate(self, queue:self.videoDataOutputQueue)
                if session.canAddOutput(videoDataOutput!){
                    session.addOutput(videoDataOutput)
                }
                videoDataOutput.connection(with: .video)?.isEnabled = true
            }
            
            AudioServicesDisposeSystemSoundID(1108)
            photoOutput = AVCapturePhotoOutput()
            photoOutput?.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecJPEG])], completionHandler: nil)
            if session.canAddOutput(photoOutput!){
                session.addOutput(photoOutput!)
            }
            
            
            
            
            previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
            if self.isFillScale == true {
                previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
            } else {
                previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
            }
            
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

//        do{
//            if (captureDevice.hasFlash && self.cameraID == 0)
//            {
//                try captureDevice.lockForConfiguration()
//                captureDevice.torchMode = mode
////                    captureDevice.flashMode = (modeID == 2) ?(.auto):(modeID == 1 ? (.on) : (.off))
//                captureDevice.unlockForConfiguration()
//            }
//        }catch{
//            print("Device tourch Flash Error ");
//        }
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
            self.session.startRunning()
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
                self.session.startRunning()
                self.isCameraVisible = true
            }
        } else {
            if self.isCameraVisible == true {
                self.stopCamera()
                self.isCameraVisible = false
            }
        }
    }
    
    
    private var isCapturing = false

    func takePicture(path: String, flutterResult: @escaping FlutterResult) {
        guard let photoOutput = self.photoOutput else {
            flutterResult(FlutterError(code: "-100", message: "Photo output not configured", details: nil))
            return
        }
        guard !isCapturing else { return } // prevent double-taps
        isCapturing = true

        self.imageSavePath = path
        self.flutterResultTakePicture = flutterResult

        // Use JPEG settings explicitly
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])

        // Flash only if available and supported
        if captureDevice.isFlashAvailable, photoOutput.supportedFlashModes.contains(self.flashMode) {
            settings.flashMode = self.flashMode
        }

        // Optional: better quality if you enabled it on the output
        if photoOutput.isHighResolutionCaptureEnabled {
            settings.isHighResolutionPhotoEnabled = true
        }

        // Match the current preview/video orientation so the still isn’t rotated
        if let conn = photoOutput.connection(with: .video), conn.isVideoOrientationSupported {
            conn.videoOrientation = previewLayer?.connection?.videoOrientation ?? .portrait
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = (cameraPosition == .front)
            }
        }

        // Fire
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    
    func processImageFromPath(path:String,flutterResult:  @escaping FlutterResult){
        let fileURL = URL(fileURLWithPath: path)
        do {
            self.flutterResultOcr = flutterResult
            let imageData = try Data(contentsOf: fileURL)
            let image = UIImage(data: imageData)
            if image == nil {
                return
            }
            let visionImage = VisionImage(image: image!)
            visionImage.orientation = image!.imageOrientation
            print("Go TO processImage")
            processImage(visionImage: visionImage, selectedImagePath: path)
        } catch {
            print("Error loading image : \(error)")
        }
        
    }
    
    
    
    
    func imageOrientation2(
      deviceOrientation: UIDeviceOrientation,
      cameraPosition: AVCaptureDevice.Position
    ) -> UIImage.Orientation {
      switch deviceOrientation {
      case .portrait:
        return cameraPosition == .front ? .leftMirrored : .right
      case .landscapeLeft:
        return cameraPosition == .front ? .downMirrored : .up
      case .portraitUpsideDown:
        return cameraPosition == .front ? .rightMirrored : .left
      case .landscapeRight:
        return cameraPosition == .front ? .upMirrored : .down
      case .faceDown, .faceUp, .unknown:
        return .up
      }
    }
    
    
    
    
    
    
    private func currentUIOrientation() -> UIDeviceOrientation {
        let deviceOrientation = { () -> UIDeviceOrientation in
            switch UIApplication.shared.statusBarOrientation {
            case .landscapeLeft:
                return .landscapeRight
            case .landscapeRight:
                return .landscapeLeft
            case .portraitUpsideDown:
                return .portraitUpsideDown
            case .portrait, .unknown:
                return .portrait
            @unknown default:
                fatalError()
            }
        }
        guard Thread.isMainThread else {
            var currentOrientation: UIDeviceOrientation = .portrait
            DispatchQueue.main.sync {
                currentOrientation = deviceOrientation()
            }
            return currentOrientation
        }
        return deviceOrientation()
    }
    
    
    public func imageOrientation(
        fromDevicePosition devicePosition: AVCaptureDevice.Position = .back
    ) -> UIImage.Orientation {
        var deviceOrientation = UIDevice.current.orientation
        if deviceOrientation == .faceDown || deviceOrientation == .faceUp
            || deviceOrientation
            == .unknown
        {
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
            fatalError()
        }
    }
    
    func saveImage(image: UIImage) -> Bool {
        guard let data = image.jpegData(compressionQuality: 1) ?? image.pngData() else {
            return false
        }
        var fileURL : URL? = nil
        if self.imageSavePath == "" {
            guard let directory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) as NSURL else {
                return false
            }
            fileURL = directory.appendingPathComponent("pic.jpg")!
        } else  {
            fileURL = URL(fileURLWithPath: self.imageSavePath)
        }
        
        
        
        
        
        
        
        guard let directory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) as NSURL else {
            return false
        }
        do {
            try data.write(to: fileURL!)
            flutterResultTakePicture(fileURL?.path)
            //print(directory)
            return true
        } catch {
            print(error.localizedDescription)
            flutterResultTakePicture(FlutterError(code: "-103", message: error.localizedDescription, details: nil))
            return false
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        defer { isCapturing = false }

        if let error = error {
            flutterResultTakePicture(FlutterError(code: "-101", message: error.localizedDescription, details: nil))
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            flutterResultTakePicture(FlutterError(code: "-102", message: "No photo data", details: nil))
            return
        }

        // Save and resolve the Flutter result (your existing helper)
        _ = self.saveImage(image: image)

        // Safety: re-apply the last zoom, in case hardware reset it during capture
        if let device = captureDevice {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = max(1.0, min(device.videoZoomFactor, device.activeFormat.videoMaxZoomFactor))
                device.unlockForConfiguration()
            } catch {
                // non-fatal
            }
        }
    }
    
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
         
            if(textRecognizer != nil) {
                let visionImage = VisionImage(buffer: sampleBuffer)
                // base orientation from camera (your existing cached value)
                let base = imageOrientation(fromDevicePosition: cameraPosition)
                // apply forced quarter turns
                visionImage.orientation = rotate(base, turns: forcedQuarterTurns)
//                visionImage.orientation = orientation
                
                do {
                    let result = try textRecognizer?.results(in: visionImage)
                    
                    if(result?.text != "") {
                        var listLineModel: [LineModel] = []
                        
                        for b in result!.blocks {
                            for l in b.lines{
                                let lineModel : LineModel = LineModel()
                                lineModel.text = l.text
                                
                                
                                
                                for c in l.cornerPoints {
                                    lineModel.cornerPoints.append(CornerPointModel(x: c.cgPointValue.x, y: c.cgPointValue.y))
                                }
                                
                                listLineModel.append(lineModel)
                                
                            }
                        }
                        
                        
                        self.onTextRead(text: result!.text, values: listLineModel, path: "", orientation:  visionImage.orientation.rawValue)
                        
                    } else {
                        
                        self.onTextRead(text: "", values: [], path: "", orientation:  nil)
                    }
                    
                    
                    
                } catch {
                    print("can't fetch result")
                }
            }
        
        
    }
    
    func onBarcodeRead(barcode: String) {
        channel.invokeMethod("onBarcodeRead", arguments: barcode)
    }
    

    func onTextRead(text: String, values: [LineModel], path: String?, orientation: Int?) {
        let data = OcrData(text: text, path: path, orientation: orientation, lines: values)
        let jsonEncoder = JSONEncoder()
        let jsonData = try! jsonEncoder.encode(data)
        let json = String(data: jsonData, encoding: String.Encoding.utf8)
        channel.invokeMethod("onTextRead", arguments: json)
    }
    
    func textRead(text: String, values: [LineModel], path: String?, orientation: Int?) {
        
        
        let data = OcrData(text: text, path: path, orientation: orientation, lines: values)
        let jsonEncoder = JSONEncoder()
        let jsonData = try! jsonEncoder.encode(data)
        let json = String(data: jsonData, encoding: String.Encoding.utf8)
        flutterResultOcr(json)
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
            var path : String?
            path = selectedImagePath
            
            textRecognizer?.process(visionImage) { result, error in
                guard error == nil, let result = result else {
                    // Error handling
                    self.textRead(text: "Error: " + error.debugDescription, values: [], path: "", orientation: nil)
                    return
                }
                // Recognized text
                
                
                if(result.text != "") {
                    var listLineModel: [LineModel] = []
                    
                    for b in result.blocks {
                        for l in b.lines{
                            let lineModel : LineModel = LineModel()
                            lineModel.text = l.text
                            
                            
                            
                            for c in l.cornerPoints {
                                lineModel.cornerPoints
                                    .append(
                                        CornerPointModel(x: c.cgPointValue.x, y: c.cgPointValue.y))
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
    
    
    private func attachZoomGesturesIfNeeded() {
        // Avoid adding duplicates on hot-reload / rebuilds
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



    
    
    
    
}
//
//struct OcrData: Codable {
//    var text: String?
//    var path: String?
//    var orientation: Int?
//    var lines: [LineModel]=[]
//}
//
//// Encode
//
//
//class LineModel: Codable {
//    var text:String = ""
//    var cornerPoints : [CornerPointModel] = []
//}
//
//
//class CornerPointModel: Codable {
//    
//    init(x:CGFloat, y:CGFloat) {
//        self.x = x
//        self.y = y
//    }
//    
//    var x:CGFloat
//    var y:CGFloat
//}
//
//class BarcodeObject: Codable {
//    var rawValue:String? = ""
//    var value:String? = ""
//    var type:Int? = 0
//    var orientation: Int?
//    var cornerPoints : [CornerPointModel] = []
//}
//
//
//struct BarcodeData: Codable {
//    var path: String?
//    var orientation: Int?
//    var barcodes: [BarcodeObject]=[]
//}

