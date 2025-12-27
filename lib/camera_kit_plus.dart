
import 'package:camera_kit_plus/enums.dart';

import 'camera_kit_plus_platform_interface.dart';
export 'camera_kit_plus_view.dart';
export 'camera_kit_ocr_plus_view.dart';
class CameraKitPlus {
  Future<String?> getPlatformVersion() {
    return CameraKitPlusPlatform.instance.getPlatformVersion();
  }

  Future<bool> pauseCamera() {
    return CameraKitPlusPlatform.instance.pauseCamera();
  }

  Future<bool> resumeCamera() {
    return CameraKitPlusPlatform.instance.resumeCamera();
  }

  Future<bool> changeFlashMode(CameraKitPlusFlashMode mode) {
    return CameraKitPlusPlatform.instance.changeFlashMode(mode);
  }

  Future<bool> switchCamera(CameraKitPlusCameraMode mode) {
    return CameraKitPlusPlatform.instance.switchCamera(mode);
  }
  Future<bool> getCameraPermission() {
    return CameraKitPlusPlatform.instance.getCameraPermission();
  }
  Future<String?> takePicture() {
    return CameraKitPlusPlatform.instance.takePicture();
  }
  Future<bool?> setZoom(double zoom) {
    return CameraKitPlusPlatform.instance.setZoom(zoom);
  }
  Future<bool?> setOcrRotation(int degree) {
    return CameraKitPlusPlatform.instance.setOcrRotation(degree);
  }
  Future<bool?> clearOcrRotation() {
    return CameraKitPlusPlatform.instance.clearOcrRotation();
  }
  Future<bool?> setMacro(bool macro) {
    return CameraKitPlusPlatform.instance.setMacro(macro);
  }
  Future<bool?> setShowTextRectangles(bool show) {
    return CameraKitPlusPlatform.instance.setShowTextRectangles(show);
  }

  // await channel.invokeMethod('setOcrRotation', {'degrees': 90}); // rotate CW 90°
  // await channel.invokeMethod('clearOcrRotation');
}
