//
//  CameraKitPlusView.swift
//  camera_kit_plus
//
//  Created by Mahmood Bakhshayesh on 8/6/1403 AP.
//
import Flutter
import UIKit
import Foundation

class CameraKitPlusView: NSObject, FlutterPlatformView {
    private var label: UILabel

    init(frame: CGRect) {
        label = UILabel(frame: frame)
        label.text = "Hello from Native iOS View"
    }

    func view() -> UIView {
        return label
    }
}
