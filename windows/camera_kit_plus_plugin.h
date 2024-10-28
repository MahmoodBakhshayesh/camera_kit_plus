#ifndef FLUTTER_PLUGIN_CAMERA_KIT_PLUS_PLUGIN_H_
#define FLUTTER_PLUGIN_CAMERA_KIT_PLUS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace camera_kit_plus {

class CameraKitPlusPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  CameraKitPlusPlugin();

  virtual ~CameraKitPlusPlugin();

  // Disallow copy and assign.
  CameraKitPlusPlugin(const CameraKitPlusPlugin&) = delete;
  CameraKitPlusPlugin& operator=(const CameraKitPlusPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace camera_kit_plus

#endif  // FLUTTER_PLUGIN_CAMERA_KIT_PLUS_PLUGIN_H_
