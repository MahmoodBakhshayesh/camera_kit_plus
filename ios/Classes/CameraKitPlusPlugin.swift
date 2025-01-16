import Flutter
import UIKit

public class CameraKitPlusPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "camera_kit_plus", binaryMessenger: registrar.messenger())
    let instance = CameraKitPlusPlugin()
    
    let factory = CameraKitPlusViewFactory(messenger: registrar.messenger())
    let ocrFactory = CameraKitOcrPlusViewFactory(messenger: registrar.messenger())

    registrar.register(factory, withId: "camera-kit-plus-view")
    registrar.register(ocrFactory, withId: "camera-kit-ocr-plus-view")
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
