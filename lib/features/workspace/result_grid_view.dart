import 'package:flutter/widgets.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/gestures.dart'
    show
        kDoubleTapTimeout,
        kPrimaryMouseButton,
        kSecondaryMouseButton,
        PointerHoverEvent;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HardwareKeyboard, LogicalKeyboardKey;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:querya_desktop/core/security/pii_masker.dart';
import 'package:querya_desktop/core/security/pii_masking_controller.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/core/ui/querya_tooltip.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/grid_cell_editor.dart';
import 'package:querya_desktop/features/workspace/grid_cell_popover_inspector.dart';
import 'package:querya_desktop/features/workspace/grid/grid_column_sizer.dart';
import 'package:querya_desktop/features/workspace/grid/grid_selection_manager.dart';
import 'package:querya_desktop/features/workspace/grid/grid_sorting.dart';
import 'package:gap/gap.dart';
import 'package:querya_desktop/core/theme/querya_ui_colors.dart';
import 'package:querya_desktop/shared/widgets/querya_context_menu.dart';

export 'package:querya_desktop/features/workspace/grid/grid_column_sizer.dart';
export 'package:querya_desktop/features/workspace/grid/grid_selection_manager.dart';
export 'package:querya_desktop/features/workspace/grid/grid_sorting.dart';

part 'grid/grid_cell_editing.dart';
part 'grid/grid_view_layout.dart';
part 'grid/grid_pointer_selection.dart';
part 'grid/grid_clipboard_service.dart';
part 'grid/grid_cell_actions.dart';
part 'grid/grid_keyboard_navigation.dart';
part 'grid/grid_view_builder.dart';
part 'grid/grid_pii_masking.dart';
part 'grid/grid_header_renderer.dart';
part 'grid/grid_row_renderer.dart';
part 'grid/grid_cell_renderer.dart';

/// Virtualized read-only or interactive grid for SQL query results (rows + columns).
class VirtualResultGrid extends material.StatefulWidget {
  const VirtualResultGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.stagingBuffer,
    this.rowIndicesMapping,
    this.onRowSelected,
    this.onSelectionValuesChanged,
    this.onCellFocused,
    this.onFilterRequested,
    this.columnDataTypes,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final DataGridStagingBuffer? stagingBuffer;

  /// Column name → SQL type, used for hover tooltips and the inline editor.
  final Map<String, String>? columnDataTypes;
  final List<int>? rowIndicesMapping;
  final material.ValueChanged<int?>? onRowSelected;
  final material.ValueChanged<List<String>>? onSelectionValuesChanged;
  final void Function(String columnName, String cellValue, int rowIndex)?
      onCellFocused;
  final void Function(String filterExpression)? onFilterRequested;

  @override
  material.State<VirtualResultGrid> createState() => _VirtualResultGridState();
}

class _VirtualResultGridState extends material.State<VirtualResultGrid> {
  final _horizontalController = material.ScrollController();
  final _verticalController = material.ScrollController();
  final _focusNode = material.FocusNode();

  List<double> _columnWidths = const [];
  List<double> _columnOffsets = const [0];
  final List<int> _columnSampleMaxRowChars = [];
  bool _widthsNeedUpdate = true;
  bool _userHasResized = false;
  double _scrollOffset = 0;

  /// Cache for [distributeResultGridSpareWidth] (#982): sampling every
  /// column's header/content width is O(columns x sampled rows) and only
  /// needs to rerun when [_columnWidths] itself was recomputed (a new list,
  /// so `identical` catches it) or the viewport width changed, not on every
  /// `LayoutBuilder` layout pass.
  List<double> _distributedWidths = const [];
  List<double>? _distributedForColumnWidths;
  double? _distributedForAvailableWidth;

  /// Counts calls to [distributeResultGridSpareWidth], i.e. cache misses.
  @material.visibleForTesting
  int columnWidthDistributionCount = 0;

  int? _sortColumnIndex;
  ResultGridSortOrder? _sortOrder;
  int _sortVersion = 0;

  /// Last widget built per visual row, reused when a rebuild would produce the
  /// same row (see [_DataRow.sameAs]).
  final Map<int, _DataRow> _rowWidgets = {};

  /// Cache for [_activePiiKinds]: column-name based PII guesses.
  List<String>? _piiKindsSource;
  List<PiiKind?>? _piiKinds;

  // Edit callbacks live in extension methods, whose tear-offs are not equal
  // across evaluations. They are captured once so [_DataRow.sameAs] can keep
  // reusing unchanged rows.
  late final _commitEditCb = _commitEdit;
  late final _cancelEditCb = _cancelEdit;
  late final _openInspectorCb = _openInspector;

  Timer? _cellTooltipTimer;
  ResultGridCellCoordinate? _cellTooltipCoord;
  material.OverlayEntry? _cellTooltipOverlayEntry;

  @material.visibleForTesting
  int get rowWidgetsCacheCount => _rowWidgets.length;

  List<List<String>> _sortedRows = const [];
  List<int> _sortedToModelIndices = const [];

  ResultGridCellCoordinate? _selectionAnchor;
  ResultGridCellCoordinate? _selectionFocus;
  ResultGridSelection? _selection;
  ResultGridCellCoordinate? _editingCell;

  int _lastKnownStagedRowCount = -1;

  bool _isPointerDown = false;
  bool _isDragSelecting = false;
  bool _hasJustDragSelected = false;
  Offset _pointerDownGlobalPos = Offset.zero;
  Offset _pointerDownLocalPos = Offset.zero;
  Offset? _lastPointerLocalPos;

  /// Grid-level tap/double-tap tracking (#983): a single cell click used to
  /// mean a per-cell `GestureDetector`; replaced by hit-testing the down
  /// position on pointer-up (see [_cellAtOffset]) and comparing against the
  /// last qualifying tap to detect a double-tap, removing a whole
  /// GestureDetector instance per visible cell.
  DateTime? _lastTapUpTime;
  ResultGridCellCoordinate? _lastTapCell;
  Timer? _autoScrollTimer;
  Timer? _selectionValuesDebounce;
  List<double> _currentDisplayOffsets = const [0];
  double _currentAvailableWidth = 0.0;

  /// Widths and window the last build used, so a scroll tick can tell whether
  /// the set of built columns actually changes before it asks for a rebuild.
  List<double> _currentDisplayWidths = const [];
  ResultGridColumnWindow? _currentWindow;
  double _currentRowsViewportHeight = 0.0;

  /// Handlers that live in `extension _Grid* on _VirtualResultGridState`. Tearing
  /// off an extension method makes a new closure each time and two of them are
  /// never equal, so `removeListener(_onPiiMaskingChanged)` would not find what
  /// `addListener(_onPiiMaskingChanged)` stored (#1555). Keep one closure and
  /// pass that to both.
  late final void Function() _piiMaskingListener = _onPiiMaskingChanged;
  late final void Function() _horizontalScrollListener = _onHorizontalScroll;

  @override
  void initState() {
    super.initState();
    _horizontalController.addListener(_horizontalScrollListener);
    _verticalController.addListener(_onVerticalScroll);
    PiiMaskingController.instance.addListener(_piiMaskingListener);
    widget.stagingBuffer?.addListener(_onStagingBufferChanged);
    _lastKnownStagedRowCount = _baseRows.length;
    _updateSortedRows();
  }

  void _onStagingBufferChanged() {
    if (!mounted) return;
    final currentRows = _baseRows;
    final rowCountChanged = _lastKnownStagedRowCount == -1 ||
        currentRows.length != _lastKnownStagedRowCount;
    _lastKnownStagedRowCount = currentRows.length;

    setState(() {
      if (rowCountChanged) {
        _updateSortedRows();
        _widthsNeedUpdate = true;
      } else if (widget.rowIndicesMapping == null) {
        _refreshSortedRowValues(currentRows);
      } else if (_sortColumnIndex != null) {
        _updateSortedRows();
      }
    });
  }

  /// Applies staged cell values to the displayed rows without re-sorting.
  ///
  /// A cell edit does not add or remove rows, so the current visual order is
  /// kept (the edited row does not jump while typing) and only the row list is
  /// rebuilt in O(N). Sorting again happens on a sort-column change, a row
  /// insert / delete, or when the user re-applies the sort.
  void _refreshSortedRowValues(List<List<String>> rows) {
    if (_sortColumnIndex == null || _sortOrder == null) {
      _sortedRows = rows;
      return;
    }
    final order = _sortedToModelIndices;
    if (order.length != rows.length) {
      _updateSortedRows();
      return;
    }
    // Drop any in-flight isolate sort: it was computed from older values.
    _sortVersion++;
    _sortedRows = List<List<String>>.generate(
      order.length,
      (i) => rows[order[i]],
      growable: false,
    );
    _rowWidgets.removeWhere((idx, _) => idx >= _sortedRows.length);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _widthsNeedUpdate = true;
  }

  @override
  void didUpdateWidget(VirtualResultGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stagingBuffer != widget.stagingBuffer) {
      oldWidget.stagingBuffer?.removeListener(_onStagingBufferChanged);
      widget.stagingBuffer?.addListener(_onStagingBufferChanged);
      _rowWidgets.clear();
    }
    if (oldWidget.columns != widget.columns ||
        oldWidget.rows != widget.rows ||
        oldWidget.stagingBuffer != widget.stagingBuffer ||
        oldWidget.rowIndicesMapping != widget.rowIndicesMapping) {
      _widthsNeedUpdate = true;
      if (oldWidget.columns != widget.columns) {
        _userHasResized = false;
        _sortColumnIndex = null;
        _sortOrder = null;
        _selectionAnchor = null;
        _selectionFocus = null;
        _selection = null;
        _editingCell = null;
        _rowWidgets.clear();
        widget.onRowSelected?.call(null);
      }
      // With a staging buffer and no filter mapping the displayed rows come from
      // the buffer, and a cell edit is applied by [_onStagingBufferChanged]. The
      // parent handing over a fresh `rows` list for that edit must not re-sort.
      final onlyRowsChanged = oldWidget.columns == widget.columns &&
          oldWidget.stagingBuffer == widget.stagingBuffer &&
          oldWidget.rowIndicesMapping == widget.rowIndicesMapping;
      final rowsFollowBuffer =
          widget.stagingBuffer != null && widget.rowIndicesMapping == null;
      if (!(onlyRowsChanged && rowsFollowBuffer)) {
        _updateSortedRows();
      }
    }
  }

  void _onVerticalScroll() {
    _hideCellTooltip();
  }

  void _onGridPointerHover(
    PointerHoverEvent event, {
    required double rowHeight,
  }) {
    if (_sortedRows.isEmpty || widget.columns.isEmpty) {
      _hideCellTooltip();
      return;
    }

    final cell = _cellAtOffset(
      localPosition: event.localPosition,
      rowHeight: rowHeight,
    );
    if (cell == null) {
      _hideCellTooltip();
      return;
    }

    if (cell == _cellTooltipCoord) {
      return;
    }

    _hideCellTooltip();
    _cellTooltipCoord = cell;

    final rowData =
        cell.row < _sortedRows.length ? _sortedRows[cell.row] : null;
    final text = (rowData != null && cell.column < rowData.length)
        ? _maskCellText(_piiKinds, cell.column, rowData[cell.column])
        : '';
    final colName =
        cell.column < widget.columns.length ? widget.columns[cell.column] : '';
    final dataTypeName = widget.columnDataTypes?[colName];

    final tooltipMsg = ResultGridMetrics.cellTooltipMessage(
      text: text,
      dataTypeName: dataTypeName,
      columnName: colName,
    );
    if (tooltipMsg == null) return;

    _cellTooltipTimer = Timer(kQueryaTooltipWait, () {
      if (!mounted || _cellTooltipCoord != cell) return;
      _showCellTooltip(event.position, tooltipMsg);
    });
  }

  void _onGridPointerExit() {
    _hideCellTooltip();
  }

  void _showCellTooltip(Offset globalPosition, String message) {
    _hideCellTooltip(preserveCoord: true);
    final overlay = material.Overlay.maybeOf(context);
    if (overlay == null || !mounted) return;

    final cs = context.colors;
    final media = material.MediaQuery.maybeOf(context);
    final screenW = media?.size.width ?? 1920.0;
    final screenH = media?.size.height ?? 1080.0;

    final left = (globalPosition.dx + 10.0).clamp(8.0, screenW - 320.0);
    final top = (globalPosition.dy + 18.0).clamp(8.0, screenH - 120.0);

    _cellTooltipOverlayEntry = material.OverlayEntry(
      builder: (context) {
        return material.Positioned(
          left: left,
          top: top,
          child: material.IgnorePointer(
            child: material.Material(
              color: material.Colors.transparent,
              child: material.Container(
                padding: const material.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: material.BoxDecoration(
                  color: cs.popover,
                  borderRadius: BorderRadius.circular(5.0),
                  border: material.Border.all(
                    color: cs.border,
                    width: 0.8,
                  ),
                  boxShadow: const [
                    material.BoxShadow(
                      color: material.Color(0x33000000),
                      blurRadius: 6,
                      offset: material.Offset(0, 2),
                    ),
                  ],
                ),
                constraints: const material.BoxConstraints(maxWidth: 360),
                child: material.Text(
                  message,
                  style: material.TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: cs.popoverForeground,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_cellTooltipOverlayEntry!);
  }

  void _hideCellTooltip({bool preserveCoord = false}) {
    _cellTooltipTimer?.cancel();
    _cellTooltipTimer = null;
    if (!preserveCoord) {
      _cellTooltipCoord = null;
    }
    _cellTooltipOverlayEntry?.remove();
    _cellTooltipOverlayEntry?.dispose();
    _cellTooltipOverlayEntry = null;
  }

  @override
  void dispose() {
    _hideCellTooltip();
    _selectionValuesDebounce?.cancel();
    PiiMaskingController.instance.removeListener(_piiMaskingListener);
    _stopAutoScroll();
    _rowWidgets.clear();
    widget.stagingBuffer?.removeListener(_onStagingBufferChanged);
    _horizontalController.removeListener(_horizontalScrollListener);
    _horizontalController.dispose();
    _verticalController.removeListener(_onVerticalScroll);
    _verticalController.dispose();
    _focusNode.dispose();
    _sortedRows = const [];
    _sortedToModelIndices = const [];
    _columnWidths = const [];
    _columnOffsets = const [0];
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) =>
      _buildGrid(context);
}
