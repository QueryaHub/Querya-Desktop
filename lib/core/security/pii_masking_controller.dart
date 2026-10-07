import 'package:flutter/foundation.dart';

/// App-wide switch for "Mask sensitive data". Every result grid listens to it,
/// so turning it on hides values in all open grids at once (screen shares,
/// screenshots). It is a session setting: it starts off at every launch.
class PiiMaskingController extends ChangeNotifier {
  PiiMaskingController();

  static final PiiMaskingController instance = PiiMaskingController();

  bool _enabled = false;

  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  void toggle() => enabled = !_enabled;
}
