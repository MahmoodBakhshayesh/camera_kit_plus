
import Flutter
import UIKit
import Foundation
import AVFoundation


class CameraKitPlusViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return NativeView(frame: frame, messenger: messenger)
    }
}


class NativeView: NSObject, FlutterPlatformView, AVCaptureMetadataOutputObjectsDelegate {
    private var _view: UIView
//    private var captureSession: AVCaptureSession?
    let captureSession = AVCaptureSession()

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var channel: FlutterMethodChannel?
    var initCameraFinished:Bool! = false

    
    init(frame: CGRect, messenger: FlutterBinaryMessenger) {
        _view = UIView(frame: frame)
        _view.backgroundColor = UIColor.blue
        print(_view.layer.frame.size.width);
        print(_view.layer.frame.size.height);
        super.init()
        setupCamera()
        channel = FlutterMethodChannel(name: "camera_kit_plus", binaryMessenger: messenger)
       
    }

    func view() -> UIView {
        return _view
    }
    
    

    private func createNativeView() {
        print("createNativeView")
        let screenSize = UIScreen.main.bounds

        let label = UILabel()
        label.text = "Hello from Native iOS View"
        label.textAlignment = .center
        label.textColor = UIColor.black
        label.backgroundColor = UIColor.yellow

        // Set label's frame and autoresizing mask
        label.frame = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
        label.autoresizingMask = [.flexibleWidth, .flexibleTopMargin, .flexibleBottomMargin]
        label.center = _view.center // Center the label within _view
        label.textColor = UIColor.black
        print("Subviews of _view: \(_view.subviews)")  // This should include the label

        _view.addSubview(label)
        print("Subviews of _view: \(_view.subviews)")  // This should include the label

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
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            print("Your device doesn't support camera")
            return
        }

        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
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
    

    // Delegate method to handle detected barcodes
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            if let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject {
                if let stringValue = readableObject.stringValue {
                    // Barcode is detected and here is the value:
                    channel?.invokeMethod("onBarcodeScanned", arguments: readableObject.stringValue)
                    // You can use a Flutter method channel to send the barcode back to Flutter
                    AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                }
            }
        }
    }

    // Stop the capture session when the view is disposed
    func dispose() {
        captureSession.stopRunning()
    }
}
