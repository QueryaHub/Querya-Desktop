//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <refresh_rate/refresh_rate_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) refresh_rate_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "RefreshRatePlugin");
  refresh_rate_plugin_register_with_registrar(refresh_rate_registrar);
}
