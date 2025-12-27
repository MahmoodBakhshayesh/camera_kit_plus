import 'package:camera_kit_plus/enums.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'camera_kit_plus_platform_interface.dart';

/// An implementation of [CameraKitPlusPlatform] that uses method channels.
class MethodChannelCameraKitPlus extends CameraKitPlusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('camera_kit_plus');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<bool> pauseCamera() async {
    final success = await methodChannel.invokeMethod<bool>('pauseCamera');
    return success ?? false;
  }

  @override
  Future<bool> resumeCamera() async {
    final success = await methodChannel.invokeMethod<bool>('resumeCamera');
    return success ?? false;
  }

  @override
  Future<bool> changeFlashMode(CameraKitPlusFlashMode mode) async {
    final version = await methodChannel.invokeMethod<bool>('changeFlashMode', {"flashModeID": mode.index});
    return version ?? false;
  }

  @override
  Future<bool> switchCamera(CameraKitPlusCameraMode mode) async {
    final version = await methodChannel.invokeMethod<bool>('switchCamera', {"cameraID": mode.index});
    return version ?? false;
  }

  @override
  Future<bool> getCameraPermission() async {
    final permission = await methodChannel.invokeMethod<bool>('getCameraPermission');

    return permission ?? false;
  }

  @override
  Future<String?> takePicture() async {
    final permission = await methodChannel.invokeMethod<String>('takePicture', {'path': ''});

    return permission;
  }

  @override
  Future<bool?> setZoom(double zoom) async {
    final zoomChange = await methodChannel.invokeMethod<bool>('setZoom', {"zoom": zoom});

    return zoomChange;
  }

  @override
  Future<bool?> setOcrRotation(int degrees) async {
    final zoomChange = await methodChannel.invokeMethod<bool>('setOcrRotation', {"degrees": degrees});

    return zoomChange;
  }

  @override
  Future<bool?> clearOcrRotation() async {
    final zoomChange = await methodChannel.invokeMethod<bool>('clearOcrRotation');

    return zoomChange;
  }

  @override
  Future<bool?> setMacro(bool macro) async {
    bool? macroChanged;
    try {
      macroChanged = await methodChannel.invokeMethod<bool>('setMacro', {"enabled": macro});
    } catch (e) {
      print('setMacro: Error in try block:\n${e.toString()}');
      macroChanged = false;
    }

    return macroChanged;
  }

  @override
  Future<bool?> setShowTextRectangles(bool show) async {
    bool? changed;
    try {
      changed = await methodChannel.invokeMethod<bool>('setShowTextRectangles', {"show": show});
    } catch (e) {
      print('setShowTextRectangles: Error:\n${e.toString()}');
      changed = false;
    }
    return changed;
  }

// await channel.invokeMethod('setOcrRotation', {'degrees': 90}); // rotate CW 90°
// await channel.invokeMethod('clearOcrRotation');
}
