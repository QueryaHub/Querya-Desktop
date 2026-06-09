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

  /// Live preview while dragging the scale slider (not persisted).
  void setScalePreview(double value) {
    final next = _normalizeUiScale(value);
    if (next == _scale) return;
    _scale = next;
    notifyListeners();
  }

  /// Persist scale to SQLite (called on slider release).
  Future<void> commitScale(double value) async {
    await AppSettings.instance.setUiScale(value);
    _scale = await AppSettings.instance.getUiScale();
    notifyListeners();
  }

  Future<void> setScale(double value) => commitScale(value);

  double _normalizeUiScale(double value) {
    final clamped = value.clamp(kMinUiScale, kMaxUiScale);
    final steps = ((clamped - kMinUiScale) / kUiScaleStep).round();
    return (kMinUiScale + steps * kUiScaleStep).clamp(kMinUiScale, kMaxUiScale);
  }
}
