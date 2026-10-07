// ignore_for_file: invalid_use_of_protected_member

part of '../result_grid_view.dart';

/// Clipboard copy (TSV/CSV/JSON) for [VirtualResultGrid].
extension _GridClipboard on _VirtualResultGridState {
  void _copySelection(
      {bool withHeaders = false, bool asCsv = false, bool asJson = false}) {
    if (_selection == null) return;
    _copySelectionData(
      _selection!,
      withHeaders: withHeaders,
      asCsv: asCsv,
      asJson: asJson,
    );
  }

  void _handleCopyCell(
    int row,
    int column, {
    bool withHeaders = false,
    bool asCsv = false,
    bool asJson = false,
  }) {
    final sel = (_selection != null && _selection!.contains(row, column))
        ? _selection!
        : ResultGridSelection(
            startRow: row,
            startColumn: column,
            endRow: row,
            endColumn: column,
          );
    _copySelectionData(
      sel,
      withHeaders: withHeaders,
      asCsv: asCsv,
      asJson: asJson,
    );
  }

  void _copySelectionData(
    ResultGridSelection sel, {
    bool withHeaders = false,
    bool asCsv = false,
    bool asJson = false,
  }) {
    if (_sortedRows.isEmpty) return;
    String text;
    if (asJson) {
      text = sel.toJson(widget.columns, _sortedRows);
    } else if (asCsv) {
      text = sel.toCsv(
        _sortedRows,
        columns: withHeaders ? widget.columns : null,
      );
    } else {
      text = sel.toTsv(
        _sortedRows,
        columns: withHeaders ? widget.columns : null,
      );
    }
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
    }
  }

}
