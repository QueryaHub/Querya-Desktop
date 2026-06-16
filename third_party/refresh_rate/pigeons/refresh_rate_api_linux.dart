// Linux-specific pigeon schema. Regenerate with:
//   dart run pigeon --input pigeons/refresh_rate_api_linux.dart \
//     --one_language \
//     --cpp_header_out linux/refresh_rate_api.g.h \
//     --cpp_source_out linux/refresh_rate_api.g.cc \
//     --cpp_namespace refresh_rate \
//     --copyright_header pigeons/copyright.txt
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  cppHeaderOut: 'linux/refresh_rate_api.g.h',
  cppSourceOut: 'linux/refresh_rate_api.g.cc',
  cppOptions: CppOptions(namespace: 'refresh_rate'),
  copyrightHeader: 'pigeons/copyright.txt',
))

// ─── Data Classes ─────────────────────────────────────────────────

class DisplayInfoMessage {
  double? currentRate;
  double? maxRate;
  double? minRate;
  List<double?>? supportedRates;
  bool? isVariableRefreshRate;
  double? engineTargetRate;
  bool? iosProMotionEnabled;
  int? androidApiLevel;
  bool? isLowPowerMode;
  // 0=nominal, 1=fair, 2=serious, 3=critical, null=unknown
  int? thermalStateIndex;
  bool? hasAdaptiveRefreshRate;
  String? displayServer;
  int? monitorCount;
}

// ─── Host API (platform → Dart calls these) ──────────────────────
// These are what the Dart side calls INTO the platform

@HostApi()
abstract class RefreshRateHostApi {
  DisplayInfoMessage getDisplayInfo();

  // Control
  void enable();
  void disable();
  void preferMax();
  void preferDefault();
  void matchContent(double fps);
  void boost(int durationMs);
  // 0=none, 1=low, 2=normal, 3=high
  void setCategory(int categoryIndex);
  void setTouchBoost(bool enabled);

  bool isSupported();
}

// ─── Flutter API (Dart → platform listens to these) ──────────────
// These are what the platform calls UP to Dart

@FlutterApi()
abstract class RefreshRateFlutterApi {
  void onDisplayInfoChanged(DisplayInfoMessage info);
}
