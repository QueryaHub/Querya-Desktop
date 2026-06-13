import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';

/// Loads and broadcasts [AppSettings] UI scale for the widget tree.
class UiScaleController extends ChangeNotifier {
  UiScaleController._();
  static final UiScaleController instance = UiScaleController._();

  double _scale = kDefaultUiScale;
  double get scale => _scale;

  Future<void> load() async {
    _scale = await AppSettings.instance.getUiScale();
    notifyListeners();
  }

  /// Persist scale to SQLite (called on slider release).
  Future<void> commitScale(double value, {bool fine = false}) async {
    await AppSettings.instance.setUiScale(value, fine: fine);
    _scale = await AppSettings.instance.getUiScale();
    notifyListeners();
  }

  Future<void> setScale(double value, {bool fine = false}) =>
      commitScale(value, fine: fine);

  /// Normalizes a raw scale value (preset snap or 1% fine steps).
  static double normalize(double value, {bool fine = false}) {
    final clamped = value.clamp(kMinUiScale, kMaxUiScale);
    if (fine) {
      final steps = ((clamped - kMinUiScale) / kUiScaleStep).round();
      return (kMinUiScale + steps * kUiScaleStep)
          .clamp(kMinUiScale, kMaxUiScale);
    }
    return snapUiScaleToPreset(clamped);
  }
}
