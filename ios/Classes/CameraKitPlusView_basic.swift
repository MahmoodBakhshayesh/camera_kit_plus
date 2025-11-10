// //
// //  CameraKitPlusView.swift
// //  camera_kit_plus
// //
// //  Created by Mahmood Bakhshayesh on 8/6/1403 AP.
// //
// import Flutter
// import UIKit
// import Foundation
// import AVFoundation
//
// @available(iOS 13.0, *)
// class CameraKitPlusView: NSObject, FlutterPlatformView, AVCaptureMetadataOutputObjectsDelegate, AVCapturePhotoCaptureDelegate {
//     private var _view: UIView
// //    private var captureSession: AVCaptureSession?
//     var captureSession = AVCaptureSession()
//     var captureDevice : AVCaptureDevice!
//     private var previewLayer: AVCaptureVideoPreviewLayer?
//     var cameraPosition: AVCaptureDevice.Position! = .back
//
//     private var channel: FlutterMethodChannel?
//     var initCameraFinished:Bool! = false
//     var cameraID = 0
//     var hasButton = false
//     private var imageCaptureResult:FlutterResult? = nil
//     var photoOutput: AVCapturePhotoOutput?
//
//     private var minZoomFactor: CGFloat = 1.0
//     private var lastZoomFactor: CGFloat = 1.0
//     private var maxZoomFactor: CGFloat {
//         // Cap practical zoom to 8x to avoid ugly noise; raise if you want
//         return min(self.captureDevice?.activeFormat.videoMaxZoomFactor ?? 1.0, 8.0)
//     }
//
//     // Forced OCR rotation (0..3 quarter turns)
//     private var forcedQuarterTurns: Int = 0
//
//     // ===== Macro =====
//     private var isMacroEnabled: Bool = false
//
//
//     init(frame: CGRect, messenger: FlutterBinaryMessenger) {
//         _view = UIView(frame: frame)
//         _view.backgroundColor = UIColor.black
//         super.init()
//
//         setupAVCapture()
//         setupCamera()
//         channel = FlutterMethodChannel(name: "camera_kit_plus", binaryMessenger: messenger)
//         channel?.setMethodCallHandler(handle)
//
//     }
//
//     func addButtonToView() {
//         if(hasButton){
//             return
//         }
//         let button = UIButton(type: .system)
//
//         // Set the button's title
//         button.setTitle("Need Camera Permission!", for: .normal)
//         button.setTitleColor(.white, for: .normal)
//         button.backgroundColor = UIColor.black
//         button.layer.cornerRadius = 8
//
//         // Set the button's size and position
//         button.translatesAutoresizingMaskIntoConstraints = false
//
//         // Add a target-action for the button
//         button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
//
//         // Add the button to the view
//         _view.addSubview(button)
//
//         // Center the button in the view
//         NSLayoutConstraint.activate([
//             button.centerXAnchor.constraint(equalTo: _view.centerXAnchor),
//             button.centerYAnchor.constraint(equalTo: _view.centerYAnchor),
//             button.widthAnchor.constraint(equalToConstant: 250),
//             button.heightAnchor.constraint(equalToConstant: 50)
//         ])
//         hasButton = true
//     }
//
//     @objc func buttonTapped() {
//         if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
//             UIApplication.shared.open(settingsURL)
//         }
//     }
//
//     func view() -> UIView {
//         _view.isUserInteractionEnabled = true
//         attachZoomGesturesIfNeeded()
//         return _view
//     }
//
//     public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
//         let args = call.arguments
//         let myArgs = args as? [String: Any]
//         switch call.method {
//         case "getCameraPermission":
//             self.requestCameraPermission(result: result)
//             break
//         case "initCamera":
// //            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
// //                let initFlashModeID = (myArgs?["initFlashModeID"] as! Int);
// //                let modeID = (myArgs?["modeID"] as! Int);
// //                let fill = (myArgs?["fill"] as! Bool);
// //                let barcodeTypeID = (myArgs?["barcodeTypeID"] as! Int);
// //                let cameraTypeID = (myArgs?["cameraTypeID"] as! Int);
// //
// //                self.initCamera( flashMode: initFlashModeID, fill: fill, barcodeTypeID: barcodeTypeID, cameraID: cameraTypeID,modeID: modeID)
// //
// //            }
//             break
//         case "changeFlashMode":
//             let mode = (myArgs?["flashModeID"] as? Int)!
//             changeFlashMode(modeID: mode, result: result)
//             result(true)
//             break
//         case "switchCamera":
//             let cameraID = (myArgs?["cameraID"] as! Int);
//             self.switchCamera(cameraID: cameraID, result: result)
// //            self.setFlashMode(flashMode: flashModeID)
// //            self.changeFlashMode()
//             break
//         case "changeCameraVisibility":
// //            let visibility = (myArgs?["visibility"] as! Bool)
// //            self.changeCameraVisibility(visibility: visibility)
//             break
//         case "pauseCamera":
//             self.pauseCamera(result: result)
//             break
//         case "resumeCamera":
//             self.resumeCamera(result: result)
//             break
//         case "takePicture":
// //            let path = (myArgs?["path"] as! String);
//             self.captureImage(result: result)
//             break
//         case "processImageFromPath":
// //            let path = (myArgs?["path"] as! String);
// //            self.processImageFromPath(path: path, flutterResult:result)
//             break
//         case "getBarcodesFromPath":
// //            let path = (myArgs?["path"] as! String);
// //            let orientation = (myArgs?["orientation"] as! Int?);
// //            self.getBarcodeFromPath(path: path, flutterResult:result,orient: orientation)
//             break
//         case "setZoom":
//             if let z = myArgs?["zoom"] as? Double {
//                 self.setZoom(factor: CGFloat(z), animated: true)
//                 result(true)
//             } else {
//                 result(FlutterError(code: "bad_args", message: "zoom (Double) required", details: nil))
//             }
//
//         case "resetZoom":
//             self.setZoom(factor: 1.0, animated: true)
//             result(true)
//
//         case "setOcrRotation":
//             let deg = (myArgs?["degrees"] as? Int) ?? 0
//             let turns = ((deg / 90) % 4 + 4) % 4
//             self.forcedQuarterTurns = turns
//             result(true)
//
//         case "clearOcrRotation":
//             self.forcedQuarterTurns = 0
//             result(true)
//
//         // ===== New: Macro toggle from Flutter =====
//         case "setMacro":
//             let enabled = (myArgs?["enabled"] as? Bool) ?? false
//             self.setMacro(enabled: enabled)
//             result(true)
//         case "dispose":
// //            self.getCameraPermission(flutterResult: result)
//             break
//         default:
//             result(false)
//         }
//
//     }
//
//
//
//     private func createNativeView() {
//         let screenSize = UIScreen.main.bounds
//         let label = UILabel()
//         label.textAlignment = .center
//         label.textColor = UIColor.black
//         label.frame = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
//         label.autoresizingMask = [.flexibleWidth, .flexibleTopMargin, .flexibleBottomMargin]
//         label.center = _view.center // Center the label within _view
//         label.textColor = UIColor.black
//         _view.addSubview(label)
//
//     }
//
//     func requestCameraPermission(result:  @escaping FlutterResult) {
//         if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
//             UIApplication.shared.open(settingsURL)
//             print(settingsURL)
//             result(true)
//         }
//     }
//
//     func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
//         guard let imageData = photo.fileDataRepresentation() else {
//             self.imageCaptureResult?(FlutterError(code: "IMAGE_CAPTURE_FAILED", message: "Could not get image data", details: nil))
//             return
//         }
//
//         // Save image to disk
//         let filename = UUID().uuidString + ".jpg"
//         let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
//         do {
//             try imageData.write(to: fileURL)
//             self.imageCaptureResult?(fileURL.path)
//         } catch {
//             self.imageCaptureResult?(FlutterError(code: "SAVE_FAILED", message: "Could not save image", details: nil))
//         }
//     }
//
//
//     func setupAVCapture(){
// //        captureSession.sessionPreset = AVCaptureSession.Preset.high
// //        self.captureDevice = AVCaptureDevice
// //            .default(AVCaptureDevice.DeviceType.builtInWideAngleCamera,for: .video,position: .back)
//         captureSession.sessionPreset = AVCaptureSession.Preset.hd1920x1080
//
//         // pick best back camera
//             if cameraPosition == .back, let dev = bestBackCamera() {
//                 captureDevice = dev
//             } else if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) {
//                 captureDevice = dev
//             } else {
//                 return
//             }
//     }
//     @available(iOS 13.0, *)
//     private func bestBackCamera() -> AVCaptureDevice? {
//         let discovery = AVCaptureDevice.DiscoverySession(
//             deviceTypes: [
//                 .builtInUltraWideCamera,       // iPhone Pro models
//                 .builtInTripleCamera,       // iPhone Pro models
//                 .builtInDualWideCamera,     // many iPhones
//                 .builtInWideAngleCamera     // fallback
//             ],
//             mediaType: .video,
//             position: .back
//         )
//         return discovery.devices.first
//     }
//
//     func switchCamera(cameraID: Int,result:  @escaping FlutterResult){
//         print("switch camera to \(cameraID)")
//         if(cameraID == 0){
//             self.captureSession.stopRunning()
//             self.captureSession = AVCaptureSession()
//             self.captureDevice = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera,for: .video,position: .back)
//             setupCamera()
//
//         }else{
//             self.captureSession.stopRunning()
//             self.captureSession = AVCaptureSession()
//             self.captureDevice = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera,for: .video,position: .front)
//             setupCamera()
//         }
//         self.cameraID = cameraID
//         result(true)
//     }
//
//     func startSession(isFirst: Bool) {
//         DispatchQueue.main.async {
//             let rootLayer :CALayer = self._view.layer
//             rootLayer.masksToBounds = true
//             if(rootLayer.bounds.size.width != 0 && rootLayer.bounds.size.width != 0){
//                 let per = self.requestCameraPermission();
//                 if(per){
//                     self._view.frame = rootLayer.bounds
//
//                     var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
//                     previewLayer.videoGravity = .resizeAspectFill  // This makes the preview take up all available space
//                     previewLayer.frame = self._view.layer.bounds  // Set the preview layer to match the view's bounds
//                     previewLayer.backgroundColor = UIColor.black.cgColor  // For debugging purposes
//                     self._view.layer.addSublayer(previewLayer)
//                     self.captureSession.startRunning()
//                 }else{
// //                    self.addButtonToView()
//                     DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
//                         self.startSession(isFirst: isFirst)
//                     }
//                 }
//
//
//             } else {
// //                self.addButtonToView()
//                 DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
//                     self.startSession(isFirst: isFirst)
//                 }
//             }
//         }
//     }
//
//
//     func requestCameraPermission() -> Bool {
//         switch AVCaptureDevice.authorizationStatus(for: .video) {
//         case .authorized:
//             return true
//         case .notDetermined:
//             self.addButtonToView()
//             return false
//         case .denied, .restricted:
//             self.addButtonToView()
//             return false
//         @unknown default:
//             return false
//         }
//     }
//
//     private func setupCamera() {
//         print("setupCamera")
//             let videoInput: AVCaptureDeviceInput
//             do {
//                 videoInput = try AVCaptureDeviceInput(device:  self.captureDevice)
//             } catch {
// //                self.addButtonToView()
//                 print("Failed to set up camera input: \(error)")
//                 return
//             }
//
//             // Add video input to capture session
//             if captureSession.canAddInput(videoInput) == true {
//                 captureSession.addInput(videoInput)
//             } else {
// //                self.addButtonToView()
//                 print("Could not add video input to session")
//                 return
//             }
//
//             // Set up the metadata output for barcode scanning (optional)
//             let metadataOutput = AVCaptureMetadataOutput()
//             if captureSession.canAddOutput(metadataOutput) == true {
//                 captureSession.addOutput(metadataOutput)
//                 metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
//
//                 metadataOutput.metadataObjectTypes = [.ean13, .qr, .pdf417,.interleaved2of5,.code128,.aztec,.code39,.code39Mod43,.code93,.dataMatrix,.ean8,.interleaved2of5,.itf14,]  // Define the type of barcodes you want to scan
//             } else {
// //                self.addButtonToView()
//                 print("Could not add metadata output to session")
//                 return
//             }
//
//
// //        if captureSession.canAddOutput(photoOutput) {
// //            captureSession.addOutput(photoOutput)
// //        } else {
// //            print("Could not add photo output to session")
// //            return
// //        }
// //
//         AudioServicesDisposeSystemSoundID(1108)
//         photoOutput = AVCapturePhotoOutput()
//         photoOutput?.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecJPEG])], completionHandler: nil)
//         if captureSession.canAddOutput(photoOutput!){
//             captureSession.addOutput(photoOutput!)
//         }
//
//             startSession(isFirst: true)
//
//     }
//
//
//     func captureImage(result: @escaping FlutterResult) {
//         let settings = AVCapturePhotoSettings()
//         if photoOutput?.supportedFlashModes.contains(.auto) == true {
//             settings.flashMode = .auto
//         }
//
//         photoOutput?.capturePhoto(with: settings, delegate: self)
//
//         // Store the result callback to return data later
//         self.imageCaptureResult = result
//     }
//
//     func pauseCamera(result:  @escaping FlutterResult){
//         captureSession.stopRunning()
//         result(true)
//     }
//
//     func resumeCamera(result:  @escaping FlutterResult){
//         captureSession.startRunning()
//         result(true)
//     }
//
//     func setFlashMode(mode: AVCaptureDevice.TorchMode){
//
//         do{
//             if (captureDevice.hasFlash && self.cameraID == 0)
//             {
//                 try captureDevice.lockForConfiguration()
//                 captureDevice.torchMode = mode
// //                    captureDevice.flashMode = (modeID == 2) ?(.auto):(modeID == 1 ? (.on) : (.off))
//                 captureDevice.unlockForConfiguration()
//             }
//         }catch{
//             print("Device tourch Flash Error ");
//         }
//     }
//
//     func changeFlashMode(modeID: Int,result:  @escaping FlutterResult){
//         setFlashMode(mode: (modeID == 2) ?(.auto):(modeID == 1 ? (.on) : (.off)))
//         result(true)
//     }
//
//
//     // Delegate method to handle detected barcodes
//     func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
//         if let metadataObject = metadataObjects.first {
//             if let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject {
//                 if let stringValue = readableObject.stringValue {
//                     // Barcode is detected and here is the value:
//                     channel?.invokeMethod("onBarcodeScanned", arguments: readableObject.stringValue)
//
//                     var data = BarcodeData(value: readableObject.stringValue, type: intBarcodeCode(for: readableObject.type), cornerPoints: [])
//
//                     for c in readableObject.corners {
//                         data.cornerPoints.append(CornerPointModel(x: c.x, y: c.y))
//                     }
//                     let jsonEncoder = JSONEncoder()
//                     let jsonData = try! jsonEncoder.encode(data)
//                     let json = String(data: jsonData, encoding: String.Encoding.utf8)
//                     channel?.invokeMethod("onBarcodeDataScanned", arguments: json)
//
//                     // You can use a Flutter method channel to send the barcode back to Flutter
// //                    AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
//                 }
//             }
//         }
//     }
//
//     @objc private func handleDoubleTapResetZoom() {
//         setZoom(factor: 1.0, animated: true)
//     }
//
//     private func setZoom(factor: CGFloat, animated: Bool = true) {
//         guard let device = self.captureDevice else { return }
//         let clamped = max(minZoomFactor, min(factor, maxZoomFactor))
//         do {
//             try device.lockForConfiguration()
//             if animated {
//                 device.ramp(toVideoZoomFactor: clamped, withRate: 8.0)
//             } else {
//                 device.videoZoomFactor = clamped
//             }
//
//             channel?.invokeMethod("onZoomChanged", arguments: factor)
//
//             device.unlockForConfiguration()
//             lastZoomFactor = clamped
//         } catch {
//
//             print("setZoom error: \(error)")
//         }
//     }
//
//     private func applyFocusConfiguration() {
//         guard let device = captureDevice else { return }
//         do {
//             try device.lockForConfiguration()
//
//             // General AF settings
//             if device.isSmoothAutoFocusSupported {
//                 device.isSmoothAutoFocusEnabled = true
//             }
//             device.isSubjectAreaChangeMonitoringEnabled = true
//
//             // Set center focus point for stability (0..1 coordinates)
//             if device.isFocusPointOfInterestSupported {
//                 device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
//             }
//
//             // Macro bias
//             if isMacroEnabled, device.isAutoFocusRangeRestrictionSupported {
//                 device.autoFocusRangeRestriction = .near
//             } else if device.isAutoFocusRangeRestrictionSupported {
//                 device.autoFocusRangeRestriction = .none
//             }
//
//             // Use continuous AF, falling back to auto focus
//             if device.isFocusModeSupported(.continuousAutoFocus) {
//                 device.focusMode = .continuousAutoFocus
//             } else if device.isFocusModeSupported(.autoFocus) {
//                 device.focusMode = .autoFocus
//             }
//
//             // (Optional) slight manual nudge toward near focus if supported
//             // Uncomment if you want a stronger macro bias:
//             // if isMacroEnabled, device.isFocusModeSupported(.locked) {
//             //     let near: Float = 0.85 // 0.0 = far, 1.0 = near (approx)
//             //     device.setFocusModeLocked(lensPosition: near) { _ in }
//             // }
//             channel?.invokeMethod("onMacroChanged", arguments: self.buildMacroStatus())
//
//             device.unlockForConfiguration()
//         } catch {
//             print("applyFocusConfiguration error: \(error)")
//         }
//     }
//
//     private func buildMacroStatus() -> [String: Any] {
//         print("buildMacroStatus")
//         var status: [String: Any] = [
//             "requestedMacro": isMacroEnabled as Any
//         ]
//         guard let d = captureDevice else { return status }
//
//         status["supportsNearRestriction"] = d.isAutoFocusRangeRestrictionSupported
//         if d.isAutoFocusRangeRestrictionSupported {
//             status["autoFocusRangeRestriction"] = (d.autoFocusRangeRestriction == .near ? "near" :
//                                                    d.autoFocusRangeRestriction == .far  ? "far"  : "none")
//         }
//         status["focusMode"] = {
//             switch d.focusMode {
//             case .locked: return "locked"
//             case .autoFocus: return "autoFocus"
//             case .continuousAutoFocus: return "continuousAutoFocus"
//             @unknown default: return "unknown"
//             }
//         }()
//         status["smoothAutoFocus"] = d.isSmoothAutoFocusSupported ? d.isSmoothAutoFocusEnabled : false
//         status["subjectAreaMonitoring"] = d.isSubjectAreaChangeMonitoringEnabled
//         status["focusPOISupported"] = d.isFocusPointOfInterestSupported
//         if d.isFocusPointOfInterestSupported {
//             status["focusPOI"] = ["x": d.focusPointOfInterest.x, "y": d.focusPointOfInterest.y]
//         }
//         status["zoomFactor"] = d.videoZoomFactor
//         status["maxZoomFactor"] = d.activeFormat.videoMaxZoomFactor
//         status["deviceType"] = d.deviceType.rawValue
//         if #available(iOS 13.0, *) {
//             status["fieldOfView"] = d.activeFormat.videoFieldOfView
//         }
//         // Lens position is read-only; useful to see we're near the close end (≈1.0)
//         if d.isFocusModeSupported(.continuousAutoFocus) || d.isFocusModeSupported(.autoFocus) || d.isFocusModeSupported(.locked) {
//             status["lensPosition"] = d.lensPosition  // 0 = far, 1 = near (approximate)
//         }
//         print(status)
//         return status
//     }
//
//     @available(iOS 13.0, *)
//     private func setMacro(enabled: Bool) {
//         isMacroEnabled = enabled
//         applyFocusConfiguration()
//         // Optional: small zoom to help framing when close
//
//         if(enabled){
//             switchBackCamera(preferUltraWide: enabled)
//         }else{
//             switchBackCamera(preferUltraWide: false)
//         }
// //        if enabled { setZoom(factor: max(1.0, min(1.3, maxZoomFactor)), animated: true) }
// //        if !enabled { setZoom(factor: max(1.0, min(1.0, maxZoomFactor)), animated: true) }
//     }
//
//     @available(iOS 13.0, *)
//     private func switchBackCamera(preferUltraWide: Bool) {
//         guard cameraPosition == .back else { return }
//
//         // Choose target device
//         let target: AVCaptureDevice? = {
//             if preferUltraWide {
//                 // Macro: Ultra Wide focuses closest (on supported iPhones)
//                 return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
//                     ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
//                 ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!
//             } else {
//                 // Normal: prefer virtual multi-cam so iOS can pick best lens for zoom range
//                 return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
//                     ?? AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
//                 ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) // keep as-is if you had it
//                     ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
//             }
//         }()
//
//         guard let newDevice = target else { return }
//
//         do {
//             let newInput = try AVCaptureDeviceInput(device: newDevice)
//
//             captureSession.beginConfiguration()
//             defer { captureSession.commitConfiguration() }
//
//             // Remove ONLY existing video device inputs
//             for input in captureSession.inputs {
//                 if let dInput = input as? AVCaptureDeviceInput, dInput.device.hasMediaType(.video) {
//                     captureSession.removeInput(dInput)
//                 }
//             }
//
//             if captureSession.canAddInput(newInput) {
//                 captureSession.addInput(newInput)
//                 self.captureDevice = newDevice
//             }
//
//             // Re-apply focus / macro bias on the new device
//             applyFocusConfiguration()
//
//             // Keep your existing outputs; they remain attached to the session
//
//         } catch {
//             print("switchBackCamera error: \(error)")
//         }
//     }
//
//     private func attachZoomGesturesIfNeeded() {
//         if let grs = _view.gestureRecognizers, grs.isEmpty == false { return }
//
//         let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
//         _view.addGestureRecognizer(pinch)
//
//         let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTapResetZoom))
//         doubleTap.numberOfTapsRequired = 2
//         _view.addGestureRecognizer(doubleTap)
//     }
//
//     @objc private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
//         guard let device = self.captureDevice else { return }
//
//         switch pinch.state {
//         case .began:
//             lastZoomFactor = device.videoZoomFactor
//
//         case .changed:
//             var newFactor = lastZoomFactor * pinch.scale
//             newFactor = max(minZoomFactor, min(newFactor, maxZoomFactor))
//             do {
//                 try device.lockForConfiguration()
//                 device.videoZoomFactor = newFactor
//                 device.unlockForConfiguration()
//             } catch {
//                 print("Zoom lock error: \(error)")
//             }
//
//         case .ended, .cancelled, .failed:
//             let target = max(minZoomFactor, min(device.videoZoomFactor, maxZoomFactor))
//             do {
//                 try device.lockForConfiguration()
//                 device.ramp(toVideoZoomFactor: target, withRate: 8.0)
//                 channel?.invokeMethod("onZoomChanged", arguments: target)
//                 device.unlockForConfiguration()
//             } catch {
//                 print("Zoom end error: \(error)")
//             }
//             lastZoomFactor = target
//
//         default: break
//         }
//     }
//
//
//     // Stop the capture session when the view is disposed
//     func dispose() {
//         captureSession.stopRunning()
//     }
// }
//
//
// struct BarcodeData: Codable {
//     var value: String?
//     var type: Int?
//     var cornerPoints : [CornerPointModel] = []
// }
//
// func intBarcodeCode(for type: AVMetadataObject.ObjectType) -> Int {
//     switch type {
//     case .aztec:
//         return 4096
//     case .code39:
//         return 2
//     case .code39Mod43:
//         return 2 // Android doesn't distinguish between Code 39 and Code 39 Mod 43
//     case .code93:
//         return 4
//     case .code128:
//         return 1
//     case .dataMatrix:
//         return 16
//     case .ean8:
//         return 64
//     case .ean13:
//         return 32
//     case .interleaved2of5:
//         return 128
//     case .itf14:
//         return 128 // Android uses the same code for ITF and Interleaved 2 of 5
//     case .pdf417:
//         return 2048
//     case .qr:
//         return 256
//     default:
//         return 0 // Unknown or unsupported type
//     }
// }
//
// // Encode
//
//
