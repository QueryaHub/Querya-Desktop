import 'package:flutter/foundation.dart';
import 'package:querya_desktop/shared/services/data_export_service.dart';

/// Lets the Command Palette hit the same ResultsTab handlers as the toolbar.
class DataGridCommandBridge {
  DataGridCommandBridge._();

  static final DataGridCommandBridge instance = DataGridCommandBridge._();

  VoidCallback? _onToggleFilter;
  VoidCallback? _onToggleInspector;
  void Function(DataExportFormat format)? _onCopy;
  VoidCallback? _onSaveExport;
  VoidCallback? _onApplyStaged;
  bool Function()? _canApplyStaged;
  var _hasRows = false;

  bool get isActive => _onToggleFilter != null;
  bool get canCopy => isActive && _hasRows;
  bool get canApplyStaged => _canApplyStaged?.call() ?? false;

  void register({
    required VoidCallback onToggleFilter,
    required VoidCallback onToggleInspector,
    required void Function(DataExportFormat format) onCopy,
    required VoidCallback onSaveExport,
    VoidCallback? onApplyStaged,
    bool Function()? canApplyStaged,
    bool hasRows = false,
  }) {
    _onToggleFilter = onToggleFilter;
    _onToggleInspector = onToggleInspector;
    _onCopy = onCopy;
    _onSaveExport = onSaveExport;
    _onApplyStaged = onApplyStaged;
    _canApplyStaged = canApplyStaged;
    _hasRows = hasRows;
  }

  void unregister() {
    _onToggleFilter = null;
    _onToggleInspector = null;
    _onCopy = null;
    _onSaveExport = null;
    _onApplyStaged = null;
    _canApplyStaged = null;
    _hasRows = false;
  }

  void invokeToggleFilter() => _onToggleFilter?.call();
  void invokeToggleInspector() => _onToggleInspector?.call();
  void invokeCopy(DataExportFormat format) => _onCopy?.call(format);
  void invokeSaveExport() => _onSaveExport?.call();
  void invokeApplyStaged() => _onApplyStaged?.call();

  @visibleForTesting
  void resetForTest() => unregister();
}
