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


class CameraKitPlusView: NSObject, FlutterPlatformView, AVCaptureMetadataOutputObjectsDelegate {
    private var _view: UIView
//    private var captureSession: AVCaptureSession?
    let captureSession = AVCaptureSession()
    var captureDevice : AVCaptureDevice!
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var channel: FlutterMethodChannel?
    var initCameraFinished:Bool! = false

    
    init(frame: CGRect, messenger: FlutterBinaryMessenger) {
        _view = UIView(frame: frame)
        _view.backgroundColor = UIColor.blue
        super.init()
        setupCamera()
        channel = FlutterMethodChannel(name: "camera_kit_plus", binaryMessenger: messenger)
        channel?.setMethodCallHandler(handle)
       
    }

    func view() -> UIView {
        return _view
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments
        let myArgs = args as? [String: Any]
        switch call.method {
        case "getCameraPermission":
//            self.getCameraPermission(flutterResult: result)
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
//            self.takePicture(path:path,flutterResult: result)
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
    
    
    func setupAVCapture(){
        captureSession.sessionPreset = AVCaptureSession.Preset.high
        guard let device = AVCaptureDevice
            .default(AVCaptureDevice.DeviceType.builtInWideAngleCamera,for: .video,position: .back) else {
            return
        }
        
        

    }
    
    func startSession(isFirst: Bool) {
        DispatchQueue.main.async {
            let rootLayer :CALayer = self._view.layer
            rootLayer.masksToBounds = true
            if(rootLayer.bounds.size.width != 0 && rootLayer.bounds.size.width != 0){
                self._view.frame = rootLayer.bounds
                var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                previewLayer.videoGravity = .resizeAspectFill  // This makes the preview take up all available space
                previewLayer.frame = self._view.layer.bounds  // Set the preview layer to match the view's bounds
                previewLayer.backgroundColor = UIColor.green.cgColor  // For debugging purposes
                self._view.layer.addSublayer(previewLayer)
                self.captureSession.startRunning()
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    self.startSession(isFirst: isFirst)
                }
            }
        }
    }
    
    private func setupCamera() {
        print("setupCamera")
        
        // Set the video capture device to the default camera
        self.captureDevice = AVCaptureDevice.default(for: .video)
        setFlashMode(mode: .off)
        
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device:  self.captureDevice)
        } catch {
            print("Failed to set up camera input: \(error)")
            return
        }

        // Add video input to capture session
        if captureSession.canAddInput(videoInput) == true {
            captureSession.addInput(videoInput)
        } else {
            print("Could not add video input to session")
            return
        }

        // Set up the metadata output for barcode scanning (optional)
        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) == true {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean13, .qr, .pdf417,.interleaved2of5,]  // Define the type of barcodes you want to scan
        } else {
            print("Could not add metadata output to session")
            return
        }
        startSession(isFirst: true)
       
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
            if (captureDevice.hasFlash)
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

