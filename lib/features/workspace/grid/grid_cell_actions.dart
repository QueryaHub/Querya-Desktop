// ignore_for_file: invalid_use_of_protected_member

part of '../result_grid_view.dart';

/// Context-menu cell and row actions for [VirtualResultGrid].
extension _GridCellActions on _VirtualResultGridState {
  void _handleFilterByValue(int row, int col, {required bool invert}) {
    if (widget.onFilterRequested == null) return;
    if (_isPiiMasked(col)) return;
    if (col >= widget.columns.length || row >= _sortedRows.length) return;
    final colName = widget.columns[col];
    final rowData = _sortedRows[row];
    final cellVal = col < rowData.length ? rowData[col] : '';

    String expr;
    if (cellVal == 'NULL') {
      expr = invert ? '$colName IS NOT NULL' : '$colName IS NULL';
    } else if (num.tryParse(cellVal) != null) {
      expr = invert ? '$colName != $cellVal' : '$colName = $cellVal';
    } else {
      final escaped = cellVal.replaceAll("'", "''");
      expr = invert ? "$colName != '$escaped'" : "$colName = '$escaped'";
    }
    widget.onFilterRequested!(expr);
  }

  void _handleFilterComparison(int row, int col, String operator) {
    if (widget.onFilterRequested == null) return;
    if (_isPiiMasked(col)) return;
    if (col >= widget.columns.length || row >= _sortedRows.length) return;
    final colName = widget.columns[col];
    final rowData = _sortedRows[row];
    final cellVal = col < rowData.length ? rowData[col] : '';
    if (num.tryParse(cellVal) == null) return;

    widget.onFilterRequested!('$colName $operator $cellVal');
  }

  void _handleSetNull(int row, int col) {
    if (widget.stagingBuffer == null) return;
    final sel = (_selection != null && _selection!.contains(row, col))
        ? _selection!
        : ResultGridSelection(
            startRow: row, startColumn: col, endRow: row, endColumn: col);
    for (var r = sel.startRow; r <= sel.endRow; r++) {
      final modelRow = _toModelRowIndex(r);
      for (var c = sel.startColumn; c <= sel.endColumn; c++) {
        widget.stagingBuffer!.setCellNull(modelRow, c);
      }
    }
  }

  void _handleSetEmpty(int row, int col) {
    if (widget.stagingBuffer == null) return;
    final sel = (_selection != null && _selection!.contains(row, col))
        ? _selection!
        : ResultGridSelection(
            startRow: row, startColumn: col, endRow: row, endColumn: col);
    for (var r = sel.startRow; r <= sel.endRow; r++) {
      final modelRow = _toModelRowIndex(r);
      for (var c = sel.startColumn; c <= sel.endColumn; c++) {
        widget.stagingBuffer!.setCell(modelRow, c, '');
      }
    }
  }

  void _handleRevertCell(int row, int col) {
    if (widget.stagingBuffer == null) return;
    final sel = (_selection != null && _selection!.contains(row, col))
        ? _selection!
        : ResultGridSelection(
            startRow: row, startColumn: col, endRow: row, endColumn: col);
    for (var r = sel.startRow; r <= sel.endRow; r++) {
      final modelRow = _toModelRowIndex(r);
      for (var c = sel.startColumn; c <= sel.endColumn; c++) {
        widget.stagingBuffer!.revertCell(modelRow, c);
      }
    }
  }

  void _handleDuplicateRow(int row) {
    if (widget.stagingBuffer == null || row >= _sortedRows.length) return;
    widget.stagingBuffer!.duplicateRow(_toModelRowIndex(row));
  }

  void _handleToggleDeleteRow(int row) {
    if (widget.stagingBuffer == null || row >= _sortedRows.length) return;
    widget.stagingBuffer!.toggleDeleteRow(_toModelRowIndex(row));
  }

  void _handleRevertRow(int row) {
    if (widget.stagingBuffer == null || row >= _sortedRows.length) return;
    widget.stagingBuffer!.revertRow(_toModelRowIndex(row));
  }

  void _openCellContextMenu(int row, int col, material.Offset globalPosition) {
    showQueryaContextMenuBuilder(
      context: context,
      // The pointer position is in window coordinates; the menu is zoomed.
      position: context.windowToApp(globalPosition),
      itemsBuilder: (ctx) => _buildCellContextMenuItems(ctx, row, col),
    );
  }

  List<material.Widget> _buildCellContextMenuItems(
    material.BuildContext context,
    int row,
    int column,
  ) {
    gridCellContextMenuItemsBuiltCount++;
    final rowData = row < _sortedRows.length ? _sortedRows[row] : null;
    final text = (rowData != null && column < rowData.length)
        ? rowData[column]
        : '';
    final columnName =
        column < widget.columns.length ? widget.columns[column] : '';
    final preview = text.length > 24 ? '${text.substring(0, 22)}…' : text;
    final isNull = text == 'NULL';
    final numVal = num.tryParse(text);
    final canFilter = widget.onFilterRequested != null;
    final hasStagingBuffer = widget.stagingBuffer != null;
    final modelRow = _toModelRowIndex(row);
    final rowStatus = widget.stagingBuffer?.getRowStatus(modelRow) ??
        StagedRowStatus.unchanged;
    final cellStatus = widget.stagingBuffer?.getCellStatus(modelRow, column) ??
        StagedCellStatus.clean;
    final cs = context.colors;

    return [
      QueryaMenuItem(
        leading:
            const material.Icon(material.Icons.content_copy_rounded, size: 16),
        trailing: const material.Text('Ctrl+C',
            style: material.TextStyle(fontSize: 11)),
        onPressed: (_) => _handleCopyCell(row, column),
        child: const material.Text('Copy Value'),
      ),
      QueryaMenuItem(
        leading:
            const material.Icon(material.Icons.table_chart_outlined, size: 16),
        trailing: const material.Text('Ctrl+Shift+C',
            style: material.TextStyle(fontSize: 11)),
        onPressed: (_) => _handleCopyCell(row, column, withHeaders: true),
        child: const material.Text('Copy with Headers'),
      ),
      QueryaMenuItem(
        leading:
            const material.Icon(material.Icons.data_object_rounded, size: 16),
        onPressed: (_) => _handleCopyCell(row, column, asJson: true),
        child: const material.Text('Copy as JSON'),
      ),
      QueryaMenuItem(
        leading: const material.Icon(material.Icons.grid_on_rounded, size: 16),
        onPressed: (_) => _handleCopyCell(row, column, asCsv: true),
        child: const material.Text('Copy as CSV'),
      ),
      if (canFilter && columnName.isNotEmpty) ...[
        const QueryaMenuDivider(),
        QueryaMenuItem(
          leading:
              const material.Icon(material.Icons.filter_alt_outlined, size: 16),
          onPressed: (_) => _handleFilterByValue(row, column, invert: false),
          child: material.Text(
            isNull
                ? 'Filter by NULL ($columnName IS NULL)'
                : 'Filter by Value ($columnName = $preview)',
          ),
        ),
        QueryaMenuItem(
          leading: const material.Icon(material.Icons.filter_alt_off_outlined,
              size: 16),
          onPressed: (_) => _handleFilterByValue(row, column, invert: true),
          child: material.Text(
            isNull
                ? 'Filter Out NULL ($columnName IS NOT NULL)'
                : 'Filter Out ($columnName != $preview)',
          ),
        ),
        if (numVal != null) ...[
          QueryaMenuItem(
            leading: const material.Icon(material.Icons.chevron_right_rounded,
                size: 16),
            onPressed: (_) => _handleFilterComparison(row, column, '>'),
            child: material.Text('Filter > $text ($columnName > $text)'),
          ),
          QueryaMenuItem(
            leading: const material.Icon(material.Icons.chevron_left_rounded,
                size: 16),
            onPressed: (_) => _handleFilterComparison(row, column, '<'),
            child: material.Text('Filter < $text ($columnName < $text)'),
          ),
        ],
      ],
      const QueryaMenuDivider(),
      QueryaMenuItem(
        leading:
            const material.Icon(material.Icons.visibility_outlined, size: 16),
        trailing: const material.Text('Ctrl+I',
            style: material.TextStyle(fontSize: 11)),
        onPressed: (_) => _openInspector(row, column),
        child: const material.Text('Inspect Cell Value…'),
      ),
      if (hasStagingBuffer) ...[
        QueryaMenuItem(
          leading: const material.Icon(
              material.Icons.remove_circle_outline_rounded,
              size: 16),
          trailing: const material.Text('Alt+N',
              style: material.TextStyle(fontSize: 11)),
          onPressed: (_) => _handleSetNull(row, column),
          child: const material.Text('Set NULL'),
        ),
        QueryaMenuItem(
          leading: const material.Icon(material.Icons.format_clear_rounded,
              size: 16),
          onPressed: (_) => _handleSetEmpty(row, column),
          child: const material.Text('Set to Empty String'),
        ),
        if (cellStatus == StagedCellStatus.modified)
          QueryaMenuItem(
            leading: const material.Icon(material.Icons.undo_rounded, size: 16),
            onPressed: (_) => _handleRevertCell(row, column),
            child: const material.Text('Revert Cell Changes'),
          ),
        const QueryaMenuDivider(),
        QueryaMenuItem(
          leading: const material.Icon(material.Icons.content_paste_go_rounded,
              size: 16),
          trailing: const material.Text('Ctrl+D',
              style: material.TextStyle(fontSize: 11)),
          onPressed: (_) => _handleDuplicateRow(row),
          child: const material.Text('Duplicate Row'),
        ),
        QueryaMenuItem(
          leading: material.Icon(
            rowStatus == StagedRowStatus.deleted
                ? material.Icons.restore_from_trash_rounded
                : material.Icons.delete_outline_rounded,
            size: 16,
            color: rowStatus == StagedRowStatus.deleted
                ? null
                : cs.destructive,
          ),
          onPressed: (_) => _handleToggleDeleteRow(row),
          child: material.Text(
            rowStatus == StagedRowStatus.deleted
                ? 'Restore Deleted Row'
                : 'Delete Row',
            style: material.TextStyle(
              color: rowStatus == StagedRowStatus.deleted
                  ? null
                  : cs.destructive,
            ),
          ),
        ),
        if (rowStatus == StagedRowStatus.modified ||
            rowStatus == StagedRowStatus.deleted)
          QueryaMenuItem(
            leading:
                const material.Icon(material.Icons.restore_rounded, size: 16),
            onPressed: (_) => _handleRevertRow(row),
            child: const material.Text('Revert Row Changes'),
          ),
      ],
    ];
  }
}
