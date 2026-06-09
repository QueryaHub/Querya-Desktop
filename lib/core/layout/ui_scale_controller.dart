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

  Future<void> setScale(double value) async {
    await AppSettings.instance.setUiScale(value);
    _scale = await AppSettings.instance.getUiScale();
    notifyListeners();
  }
}
