import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'camera_kit_plus_method_channel.dart';

abstract class CameraKitPlusPlatform extends PlatformInterface {
  /// Constructs a CameraKitPlusPlatform.
  CameraKitPlusPlatform() : super(token: _token);

  static final Object _token = Object();

  static CameraKitPlusPlatform _instance = MethodChannelCameraKitPlus();

  /// The default instance of [CameraKitPlusPlatform] to use.
  ///
  /// Defaults to [MethodChannelCameraKitPlus].
  static CameraKitPlusPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [CameraKitPlusPlatform] when
  /// they register themselves.
  static set instance(CameraKitPlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}