import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'querya_motion_scope.dart';

/// Loads and broadcasts [AppSettings] motion level for the widget tree.
class QueryaMotionController extends ChangeNotifier {
  QueryaMotionController._();
  static final QueryaMotionController instance = QueryaMotionController._();

  QueryaMotionLevel _level = QueryaMotionLevel.full;
  QueryaMotionLevel get level => _level;

  Future<void> load() async {
    _level = await AppSettings.instance.getMotionLevel();
    notifyListeners();
  }

  Future<void> setLevel(QueryaMotionLevel value) async {
    if (_level == value) return;
    await AppSettings.instance.setMotionLevel(value);
    _level = value;
    notifyListeners();
  }
}
