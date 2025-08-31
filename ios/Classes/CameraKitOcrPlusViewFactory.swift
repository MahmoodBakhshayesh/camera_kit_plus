
import Flutter
import UIKit
import Foundation
import AVFoundation


@available(iOS 13.0, *)
class CameraKitOcrPlusViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
//        return CameraKitOcrPlusView(frame: frame, messenger: messenger)
        return CameraKitOcrView(frame: frame, viewIdentifier: 1, arguments: nil, binaryMessenger: messenger)
    }
}


