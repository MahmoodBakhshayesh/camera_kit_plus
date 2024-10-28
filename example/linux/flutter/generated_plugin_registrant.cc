//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <camera_kit_plus/camera_kit_plus_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) camera_kit_plus_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "CameraKitPlusPlugin");
  camera_kit_plus_plugin_register_with_registrar(camera_kit_plus_registrar);
}
