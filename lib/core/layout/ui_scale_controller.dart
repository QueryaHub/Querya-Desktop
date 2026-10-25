import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/util/log_ignored.dart';

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

  /// Applies [value] at once and then stores it (called on slider release).
  ///
  /// The interface changes before the database is touched, so a slow or failing
  /// write never delays or undoes what the user just chose; a failed write is
  /// logged and the scale applies until the next start.
  Future<void> commitScale(double value, {bool fine = false}) async {
    _scale = normalize(value, fine: fine);
    notifyListeners();
    try {
      await AppSettings.instance.setUiScale(_scale, fine: true);
    } catch (e, st) {
      logIgnored('UiScaleController.commitScale', e, st);
    }
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
