import 'package:flutter_test/flutter_test.dart';
import 'package:camera_kit_plus/camera_kit_plus.dart';
import 'package:camera_kit_plus/camera_kit_plus_platform_interface.dart';
import 'package:camera_kit_plus/camera_kit_plus_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockCameraKitPlusPlatform
    with MockPlatformInterfaceMixin
    implements CameraKitPlusPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final CameraKitPlusPlatform initialPlatform = CameraKitPlusPlatform.instance;

  test('$MethodChannelCameraKitPlus is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelCameraKitPlus>());
  });

  test('getPlatformVersion', () async {
    CameraKitPlus cameraKitPlusPlugin = CameraKitPlus();
    MockCameraKitPlusPlatform fakePlatform = MockCameraKitPlusPlatform();
    CameraKitPlusPlatform.instance = fakePlatform;

    expect(await cameraKitPlusPlugin.getPlatformVersion(), '42');
  });
}
