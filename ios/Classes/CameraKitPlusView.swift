//
//  CameraKitPlusView.swift
//  camera_kit_plus
//
//  Created by Mahmood Bakhshayesh on 8/6/1403 AP.
//
import Flutter
import UIKit
import Foundation
import AVFoundation


class CameraKitPlusView: NSObject, FlutterPlatformView, AVCaptureMetadataOutputObjectsDelegate, AVCapturePhotoCaptureDelegate {
    private var _view: UIView
//    private var captureSession: AVCaptureSession?
    var captureSession = AVCaptureSession()
    var captureDevice : AVCaptureDevice!
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var channel: FlutterMethodChannel?
    var initCameraFinished:Bool! = false
    var cameraID = 0
    var hasButton = false
    private var imageCaptureResult:FlutterResult? = nil
    var photoOutput: AVCapturePhotoOutput?

    
    init(frame: CGRect, messenger: FlutterBinaryMessenger) {
        _view = UIView(frame: frame)
        _view.backgroundColor = UIColor.black
        super.init()
       
        setupAVCapture()
        setupCamera()
        channel = FlutterMethodChannel(name: "camera_kit_plus", binaryMessenger: messenger)
        channel?.setMethodCallHandler(handle)
       
    }
    
    func addButtonToView() {
        if(hasButton){
            return
        }
        let button = UIButton(type: .system)
        
        // Set the button's title
        button.setTitle("Need Camera Permission!", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.black
        button.layer.cornerRadius = 8

        // Set the button's size and position
        button.translatesAutoresizingMaskIntoConstraints = false

        // Add a target-action for the button
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)

        // Add the button to the view
        _view.addSubview(button)

        // Center the button in the view
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: _view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: _view.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 250),
            button.heightAnchor.constraint(equalToConstant: 50)
        ])
        hasButton = true
    }

    @objc func buttonTapped() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
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
            self.changeFlashMode(modeID: flashModeID, result: result)
//            self.setFlashMode(flashMode: flashModeID)
//            self.changeFlashMode()
            break
        case "switchCamera":
            let cameraID = (myArgs?["cameraID"] as! Int);
            self.switchCamera(cameraID: cameraID, result: result)
//            self.setFlashMode(flashMode: flashModeID)
//            self.changeFlashMode()
            break
        case "changeCameraVisibility":
//            let visibility = (myArgs?["visibility"] as! Bool)
//            self.changeCameraVisibility(visibility: visibility)
            break
        case "pauseCamera":
            self.pauseCamera(result: result)
            break
        case "resumeCamera":
            self.resumeCamera(result: result)
            break
        case "takePicture":
//            let path = (myArgs?["path"] as! String);
            self.captureImage(result: result)
            break
        case "processImageFromPath":
//            let path = (myArgs?["path"] as! String);
//            self.processImageFromPath(path: path, flutterResult:result)
            break
        case "getBarcodesFromPath":
//            let path = (myArgs?["path"] as! String);
//            let orientation = (myArgs?["orientation"] as! Int?);
//            self.getBarcodeFromPath(path: path, flutterResult:result,orient: orientation)
            break
        case "dispose":
//            self.getCameraPermission(flutterResult: result)
            break
        default:
            result(false)
        }
        
    }
    
    

    private func createNativeView() {
        let screenSize = UIScreen.main.bounds
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = UIColor.black
        label.frame = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
        label.autoresizingMask = [.flexibleWidth, .flexibleTopMargin, .flexibleBottomMargin]
        label.center = _view.center // Center the label within _view
        label.textColor = UIColor.black
        _view.addSubview(label)

    }
    
    func requestCameraPermission(result:  @escaping FlutterResult) {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
            print(settingsURL)
            result(true)
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation() else {
            self.imageCaptureResult?(FlutterError(code: "IMAGE_CAPTURE_FAILED", message: "Could not get image data", details: nil))
            return
        }

        // Save image to disk
        let filename = UUID().uuidString + ".jpg"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try imageData.write(to: fileURL)
            self.imageCaptureResult?(fileURL.path)
        } catch {
            self.imageCaptureResult?(FlutterError(code: "SAVE_FAILED", message: "Could not save image", details: nil))
        }
    }
    
    
    func setupAVCapture(){
        captureSession.sessionPreset = AVCaptureSession.Preset.high
        self.captureDevice = AVCaptureDevice
            .default(AVCaptureDevice.DeviceType.builtInWideAngleCamera,for: .video,position: .back)
    }
    
    func switchCamera(cameraID: Int,result:  @escaping FlutterResult){
        print("switch camera to \(cameraID)")
        if(cameraID == 0){
            self.captureSession.stopRunning()
            self.captureSession = AVCaptureSession()
            self.captureDevice = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera,for: .video,position: .back)
            setupCamera()
            
        }else{
            self.captureSession.stopRunning()
            self.captureSession = AVCaptureSession()
            self.captureDevice = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera,for: .video,position: .front)
            setupCamera()
        }
        self.cameraID = cameraID
        result(true)
    }
    
    func startSession(isFirst: Bool) {
        DispatchQueue.main.async {
            let rootLayer :CALayer = self._view.layer
            rootLayer.masksToBounds = true
            if(rootLayer.bounds.size.width != 0 && rootLayer.bounds.size.width != 0){
                let per = self.requestCameraPermission();
                if(per){
                    self._view.frame = rootLayer.bounds
                   
                    var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                    previewLayer.videoGravity = .resizeAspectFill  // This makes the preview take up all available space
                    previewLayer.frame = self._view.layer.bounds  // Set the preview layer to match the view's bounds
                    previewLayer.backgroundColor = UIColor.black.cgColor  // For debugging purposes
                    self._view.layer.addSublayer(previewLayer)
                    self.captureSession.startRunning()
                }else{
//                    self.addButtonToView()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        self.startSession(isFirst: isFirst)
                    }
                }
                
              
            } else {
//                self.addButtonToView()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    self.startSession(isFirst: isFirst)
                }
            }
        }
    }
    
    
    func requestCameraPermission() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            self.addButtonToView()
            return false
        case .denied, .restricted:
            self.addButtonToView()
            return false
        @unknown default:
            return false
        }
    }
    
    private func setupCamera() {
        print("setupCamera")
            let videoInput: AVCaptureDeviceInput
            do {
                videoInput = try AVCaptureDeviceInput(device:  self.captureDevice)
            } catch {
//                self.addButtonToView()
                print("Failed to set up camera input: \(error)")
                return
            }
            
            // Add video input to capture session
            if captureSession.canAddInput(videoInput) == true {
                captureSession.addInput(videoInput)
            } else {
//                self.addButtonToView()
                print("Could not add video input to session")
                return
            }
            
            // Set up the metadata output for barcode scanning (optional)
            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) == true {
                captureSession.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                
                metadataOutput.metadataObjectTypes = [.ean13, .qr, .pdf417,.interleaved2of5,.code128,.aztec,.code39,.code39Mod43,.code93,.dataMatrix,.ean8,.interleaved2of5,.itf14,]  // Define the type of barcodes you want to scan
            } else {
//                self.addButtonToView()
                print("Could not add metadata output to session")
                return
            }
        
        
//        if captureSession.canAddOutput(photoOutput) {
//            captureSession.addOutput(photoOutput)
//        } else {
//            print("Could not add photo output to session")
//            return
//        }
//        
        AudioServicesDisposeSystemSoundID(1108)
        photoOutput = AVCapturePhotoOutput()
        photoOutput?.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecJPEG])], completionHandler: nil)
        if captureSession.canAddOutput(photoOutput!){
            captureSession.addOutput(photoOutput!)
        }
        
            startSession(isFirst: true)
       
    }
    
    
    func captureImage(result: @escaping FlutterResult) {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        
        photoOutput?.capturePhoto(with: settings, delegate: self)

        // Store the result callback to return data later
        self.imageCaptureResult = result
    }
    
    func pauseCamera(result:  @escaping FlutterResult){
        captureSession.stopRunning()
        result(true)
    }
    
    func resumeCamera(result:  @escaping FlutterResult){
        captureSession.startRunning()
        result(true)
    }
    
    func setFlashMode(mode: AVCaptureDevice.TorchMode){
        
        do{
            if (captureDevice.hasFlash && self.cameraID == 0)
            {
                try captureDevice.lockForConfiguration()
                captureDevice.torchMode = mode
//                    captureDevice.flashMode = (modeID == 2) ?(.auto):(modeID == 1 ? (.on) : (.off))
                captureDevice.unlockForConfiguration()
            }
        }catch{
            print("Device tourch Flash Error ");
        }
    }
    
    func changeFlashMode(modeID: Int,result:  @escaping FlutterResult){
        setFlashMode(mode: (modeID == 2) ?(.auto):(modeID == 1 ? (.on) : (.off)))
        result(true)
    }
    

    // Delegate method to handle detected barcodes
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            if let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject {
                if let stringValue = readableObject.stringValue {
                    // Barcode is detected and here is the value:
                    channel?.invokeMethod("onBarcodeScanned", arguments: readableObject.stringValue)
                    
                    var data = BarcodeData(value: readableObject.stringValue, type: intBarcodeCode(for: readableObject.type), cornerPoints: [])

                    for c in readableObject.corners {
                        data.cornerPoints.append(CornerPointModel(x: c.x, y: c.y))
                    }
                    let jsonEncoder = JSONEncoder()
                    let jsonData = try! jsonEncoder.encode(data)
                    let json = String(data: jsonData, encoding: String.Encoding.utf8)
                    channel?.invokeMethod("onBarcodeDataScanned", arguments: json)
                    
                    // You can use a Flutter method channel to send the barcode back to Flutter
//                    AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                }
            }
        }
    }

    // Stop the capture session when the view is disposed
    func dispose() {
        captureSession.stopRunning()
    }
}


struct BarcodeData: Codable {
    var value: String?
    var type: Int?
    var cornerPoints : [CornerPointModel] = []
}

func intBarcodeCode(for type: AVMetadataObject.ObjectType) -> Int {
    switch type {
    case .aztec:
        return 4096
    case .code39:
        return 2
    case .code39Mod43:
        return 2 // Android doesn't distinguish between Code 39 and Code 39 Mod 43
    case .code93:
        return 4
    case .code128:
        return 1
    case .dataMatrix:
        return 16
    case .ean8:
        return 64
    case .ean13:
        return 32
    case .interleaved2of5:
        return 128
    case .itf14:
        return 128 // Android uses the same code for ITF and Interleaved 2 of 5
    case .pdf417:
        return 2048
    case .qr:
        return 256
    default:
        return 0 // Unknown or unsupported type
    }
}

// Encode


