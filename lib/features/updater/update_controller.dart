import 'package:flutter/foundation.dart';

import '../../core/storage/app_settings.dart';
import '../../core/updater/app_updater_service.dart';
import '../../core/updater/update_manifest.dart';

/// Tracks a pending update for the title-bar badge and startup background checks.
class UpdateController extends ChangeNotifier {
  UpdateController({
    AppUpdaterService? updater,
    AppSettings? settings,
  })  : _updater = updater ?? AppUpdaterService.instance,
        _settings = settings ?? AppSettings.instance;

  final AppUpdaterService _updater;
  final AppSettings _settings;

  static final UpdateController instance = UpdateController();

  UpdateManifest? _pendingUpdate;
  String? _dismissedVersion;
  bool _initialized = false;

  UpdateManifest? get pendingUpdate => _pendingUpdate;

  bool get showBadge =>
      _pendingUpdate != null && _pendingUpdate!.version != _dismissedVersion;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _dismissedVersion = await _settings.getUpdateDismissedVersion();
    final result = await _updater.maybeCheckOnStartup();
    if (result?.hasUpdate == true && result!.availableUpdate != null) {
      _pendingUpdate = result.availableUpdate;
      notifyListeners();
    }
  }

  void setPendingUpdate(UpdateManifest? manifest) {
    _pendingUpdate = manifest;
    notifyListeners();
  }

  Future<void> remindLater() async {
    final version = _pendingUpdate?.version;
    if (version == null || version.isEmpty) return;
    _dismissedVersion = version;
    await _settings.setUpdateDismissedVersion(version);
    notifyListeners();
  }

  @visibleForTesting
  void setDismissedVersionForTest(String? version) {
    _dismissedVersion = version;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _pendingUpdate = null;
    _dismissedVersion = null;
    _initialized = false;
  }
}
