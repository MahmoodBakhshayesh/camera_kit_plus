
import 'camera_kit_plus_platform_interface.dart';
export 'camera_kit_plus_view.dart';
class CameraKitPlus {
  Future<String?> getPlatformVersion() {
    return CameraKitPlusPlatform.instance.getPlatformVersion();
  }
}
