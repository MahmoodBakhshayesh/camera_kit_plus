#include "include/camera_kit_plus/camera_kit_plus_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "camera_kit_plus_plugin.h"

void CameraKitPlusPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  camera_kit_plus::CameraKitPlusPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
