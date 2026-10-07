// ignore_for_file: invalid_use_of_protected_member

part of '../result_grid_view.dart';

/// "Mask sensitive data" support for [VirtualResultGrid].
extension _GridPiiMasking on _VirtualResultGridState {
  /// Per-column PII kind while masking is on (null when it is off). Cached per
  /// [VirtualResultGrid.columns] instance.
  List<PiiKind?>? get _activePiiKinds {
    if (!PiiMaskingController.instance.enabled) return null;
    final columns = widget.columns;
    if (!identical(_piiKindsSource, columns) || _piiKinds == null) {
      _piiKindsSource = columns;
      _piiKinds = detectPiiColumns(columns);
    }
    return _piiKinds;
  }

  /// Whether the values of [column] are hidden right now.
  bool _isPiiMasked(int column) {
    final kinds = _activePiiKinds;
    return kinds != null && column >= 0 && column < kinds.length &&
        kinds[column] != null;
  }

  /// [value] of [column] as it may be shown (or handed to side panels).
  String _maskedValue(int column, String value) {
    final kinds = _activePiiKinds;
    if (kinds == null || column < 0 || column >= kinds.length) return value;
    final kind = kinds[column];
    return kind == null ? value : maskPiiValue(kind, value);
  }

  void _onPiiMaskingChanged() {
    if (!mounted) return;
    _rowWidgets.clear();
    setState(() {});
    _notifySelectionAndFocus();
  }
}
