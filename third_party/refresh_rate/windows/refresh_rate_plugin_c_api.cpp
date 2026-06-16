// Windows implementation of RefreshRatePlugin.
//
// Uses QueryDisplayConfig for accurate refresh rates (rational numbers like 59.94Hz)
// and EnumDisplaySettings for enumerating all supported modes.
// Control is query-only on Windows — rate control requires system-level access.

#include "include/refresh_rate/refresh_rate_plugin_c_api.h"
#include "refresh_rate_api.g.h"

#include <flutter/plugin_registrar_windows.h>
#include <windows.h>
#include <wingdi.h>

#include <algorithm>
#include <cmath>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace refresh_rate {

class RefreshRatePlugin : public flutter::Plugin, public RefreshRateHostApi {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  RefreshRatePlugin();
  virtual ~RefreshRatePlugin();

  // RefreshRateHostApi
  ErrorOr<DisplayInfoMessage> GetDisplayInfo() override;
  std::optional<FlutterError> Enable() override { return std::nullopt; }
  std::optional<FlutterError> Disable() override { return std::nullopt; }
  std::optional<FlutterError> PreferMax() override { return std::nullopt; }
  std::optional<FlutterError> PreferDefault() override { return std::nullopt; }
  std::optional<FlutterError> MatchContent(double fps) override { return std::nullopt; }
  std::optional<FlutterError> Boost(int64_t duration_ms) override { return std::nullopt; }
  std::optional<FlutterError> SetCategory(int64_t category_index) override { return std::nullopt; }
  std::optional<FlutterError> SetTouchBoost(bool enabled) override { return std::nullopt; }
  ErrorOr<bool> IsSupported() override { return false; }

 private:
  double GetCurrentRate();
  double GetMaxRate();
  std::vector<double> GetSupportedRates();
  double GetCurrentRateViaQueryDisplayConfig();
  double GetCurrentRateViaEnumDisplaySettings();
};

void RefreshRatePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<RefreshRatePlugin>();
  RefreshRateHostApi::SetUp(registrar->messenger(), plugin.get());
  registrar->AddPlugin(std::move(plugin));
}

RefreshRatePlugin::RefreshRatePlugin() {}
RefreshRatePlugin::~RefreshRatePlugin() {}

double RefreshRatePlugin::GetCurrentRateViaQueryDisplayConfig() {
  UINT32 pathCount = 0, modeCount = 0;
  if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathCount, &modeCount) != ERROR_SUCCESS) {
    return 0.0;
  }
  std::vector<DISPLAYCONFIG_PATH_INFO> paths(pathCount);
  std::vector<DISPLAYCONFIG_MODE_INFO> modes(modeCount);
  if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pathCount, paths.data(),
                         &modeCount, modes.data(), nullptr) != ERROR_SUCCESS) {
    return 0.0;
  }
  for (UINT32 i = 0; i < modeCount; i++) {
    if (modes[i].infoType == DISPLAYCONFIG_MODE_INFO_TYPE_TARGET) {
      auto vsync = modes[i].targetMode.targetVideoSignalInfo.vSyncFreq;
      if (vsync.Denominator > 0) {
        return static_cast<double>(vsync.Numerator) / static_cast<double>(vsync.Denominator);
      }
    }
  }
  return 0.0;
}

double RefreshRatePlugin::GetCurrentRateViaEnumDisplaySettings() {
  DEVMODE dm;
  dm.dmSize = sizeof(dm);
  if (EnumDisplaySettings(NULL, ENUM_CURRENT_SETTINGS, &dm)) {
    double rate = static_cast<double>(dm.dmDisplayFrequency);
    if (rate > 1) return rate;
  }
  return 60.0;
}

double RefreshRatePlugin::GetCurrentRate() {
  double rate = GetCurrentRateViaQueryDisplayConfig();
  if (rate > 1.0) return rate;
  return GetCurrentRateViaEnumDisplaySettings();
}

double RefreshRatePlugin::GetMaxRate() {
  auto rates = GetSupportedRates();
  if (rates.empty()) return GetCurrentRate();
  return *std::max_element(rates.begin(), rates.end());
}

std::vector<double> RefreshRatePlugin::GetSupportedRates() {
  DEVMODE dm, current;
  dm.dmSize = sizeof(dm);
  current.dmSize = sizeof(current);
  EnumDisplaySettings(NULL, ENUM_CURRENT_SETTINGS, &current);

  std::set<double> rateSet;
  int modeNum = 0;
  while (EnumDisplaySettings(NULL, modeNum, &dm)) {
    if (dm.dmPelsWidth == current.dmPelsWidth &&
        dm.dmPelsHeight == current.dmPelsHeight &&
        dm.dmDisplayFrequency > 1) {
      rateSet.insert(static_cast<double>(dm.dmDisplayFrequency));
    }
    modeNum++;
  }
  if (rateSet.empty()) rateSet.insert(GetCurrentRate());
  return std::vector<double>(rateSet.begin(), rateSet.end());
}

ErrorOr<DisplayInfoMessage> RefreshRatePlugin::GetDisplayInfo() {
  double currentRate = GetCurrentRate();
  auto supportedRates = GetSupportedRates();
  double maxRate = supportedRates.empty() ? currentRate
      : *std::max_element(supportedRates.begin(), supportedRates.end());
  double minRate = supportedRates.empty() ? currentRate : supportedRates.front();
  bool isVRR = (maxRate - minRate > 30) && supportedRates.size() <= 4;

  flutter::EncodableList rates;
  for (double r : supportedRates) {
    rates.push_back(flutter::EncodableValue(r));
  }

  DisplayInfoMessage msg;
  msg.set_current_rate(currentRate);
  msg.set_max_rate(maxRate);
  msg.set_min_rate(minRate);
  msg.set_supported_rates(rates);
  msg.set_is_variable_refresh_rate(isVRR);
  msg.set_engine_target_rate(60.0);
  return msg;
}

}  // namespace refresh_rate

void RefreshRatePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  refresh_rate::RefreshRatePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
