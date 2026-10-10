import 'dart:async';
import 'dart:convert';
import 'dart:math' show max, min;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LogicalKeyboardKey;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/features/erd/erd_canvas_controls.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/features/erd/erd_geometry.dart';
import 'package:querya_desktop/features/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/features/erd/erd_router.dart';
import 'package:querya_desktop/core/export/svg_png.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';
import 'package:querya_desktop/shared/widgets/querya_action_menu.dart';
import 'package:querya_desktop/shared/widgets/querya_empty_state.dart';
import 'package:querya_desktop/shared/widgets/querya_search_field.dart';
import 'package:querya_desktop/features/workspace/sql_editor_chrome.dart';
import 'package:querya_desktop/shared/widgets/querya_action_button.dart';
import 'package:querya_desktop/shared/widgets/querya_spinner.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Saves an exported diagram file; replaceable in tests.
typedef ErdFileSaver = Future<void> Function(String name, Uint8List bytes);

Future<void> defaultErdFileSaver(String name, Uint8List bytes) async {
  final ext = name.split('.').last;
  final location = await getSaveLocation(
    acceptedTypeGroups: [
      XTypeGroup(label: ext.toUpperCase(), extensions: [ext]),
    ],
    suggestedName: name,
  );
  if (location == null) return;
  await XFile.fromData(bytes, name: name).saveTo(location.path);
}

/// Interactive entity-relationship diagram of the connected database.
/// Entries of the diagram's Export menu.
enum _ExportAction { mermaid, svg, png, copyMermaid, toggleTheme }

/// A card's focus: related to the focused table, and faded while another
/// table is picked and this one is not related to it.
typedef _CardFocus = ({bool highlighted, bool faded});

/// Card builds so far. A test seam: hovering one card must not rebuild the
/// others.
@visibleForTesting
int erdCardBuilds = 0;

class ErdView extends material.StatefulWidget {
  const ErdView({
    super.key,
    required this.source,
    this.databaseName = '',
    this.focusTable,
    this.neighbourhoodDepth,
    this.onOpenTable,
    this.onOpenInSql,
    this.onShowRelations,
    this.onOpenFullDiagram,
    this.onSaveFile,
    this.layoutStore,
    this.layoutKey,
  });

  /// Keeps what the user arranged (positions, collapsed and hidden tables,
  /// keys only, zoom and pan) between sessions under [layoutKey] (#1275). A
  /// neighbourhood view is never kept: it is not the user's arrangement.
  final ErdLayoutStore? layoutStore;
  final ErdLayoutKey? layoutKey;

  /// Draw only [focusTable] and the tables within this many foreign keys.
  final int? neighbourhoodDepth;

  /// Opens the diagram's full schema, from a neighbourhood's empty state.
  final material.VoidCallback? onOpenFullDiagram;

  /// Where the tables come from.
  final ErdSource source;

  /// Table to pick and centre once the schema is drawn.
  final String? focusTable;

  /// Names the exported files: `<databaseName>-erd.svg`.
  final String databaseName;

  /// Called on double tap of a table card.
  final void Function(String table)? onOpenTable;

  /// "Open in SQL" in a card's menu: the table's rows in the SQL editor.
  final void Function(String table)? onOpenInSql;

  /// "Show relations" in a card's menu: the table browser's Relations view.
  final void Function(String table)? onShowRelations;
  final ErdFileSaver? onSaveFile;

  @override
  material.State<ErdView> createState() => _ErdViewState();
}

class _ErdViewState extends material.State<ErdView> {
  final _boundaryKey = material.GlobalKey();
  ErdSchema? _schema;
  ErdLayout? _layout;
  List<ErdRoute> _routes = const [];
  String? _error;
  bool _loading = true;

  /// Table under the mouse, the one being dragged, and the one picked by a
  /// click or search: their edges are highlighted. A picked table stays
  /// highlighted when the mouse leaves.
  final _hovered = material.ValueNotifier<String?>(null);
  String? _dragging;
  String? _selected;
  bool _routeScheduled = false;

  /// The focus the edges draw. Every card has its own notifier in
  /// [_cardStates]; [_syncFocus] moves only the ones whose focus changed, so a
  /// hover rebuilds the cards it touches and not the whole canvas.
  final _focus = material.ValueNotifier<String?>(null);
  final _cardStates = <String, material.ValueNotifier<_CardFocus>>{};
  Map<String, Set<String>> _neighbours = const {};

  /// Density: only PK and FK columns, cards collapsed to their header, and
  /// tables hidden from the diagram. Layout and routing follow the visible
  /// schema from [_visibleOf].
  bool _keysOnly = false;
  final Set<String> _collapsed = {};
  final Set<String> _hidden = {};

  /// Header colour picked per table (palette slot names, #1276).
  final Map<String, String> _headerColors = {};

  /// Relation under the pointer and the pointer position in canvas space.
  final _edgeTipNotifier =
      material.ValueNotifier<(ErdRelation, material.Offset)?>(null);

  bool _searchOpen = false;
  String _query = '';
  final _searchController = material.TextEditingController();
  final _searchFocus = material.FocusNode();
  final _canvasFocus = material.FocusNode();
  final _viewportKey = material.GlobalKey();

  final _transform = material.TransformationController();

  static const double _minScale = 0.2;
  static const double _maxScale = 3;
  static const double _zoomStep = 1.25;

  /// Lowest zoom: [_minScale], or lower when the whole diagram needs it to
  /// fit the viewport (a schema of a few hundred tables).
  double _zoomFloor = _minScale;

  /// Saves of the layout wait for a pause in the changes.
  Timer? _saveTimer;
  bool _restoring = false;

  bool get _persists =>
      widget.layoutStore != null &&
      widget.layoutKey != null &&
      widget.neighbourhoodDepth == null;

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      unawaited(_saveNow());
    }
    _transform.removeListener(_scheduleSave);
    _transform.dispose();
    _hovered.dispose();
    _focus.dispose();
    for (final card in _cardStates.values) {
      card.dispose();
    }
    _edgeTipNotifier.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _canvasFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocus);
    _hovered.addListener(_syncFocus);
    _transform.addListener(_scheduleSave);
    _load();
  }

  /// The search field handles Esc itself: the first clears the text, the
  /// next drops the focus, so the view's own Esc never sees it. An empty
  /// search that loses the focus closes, and the canvas gets the keyboard
  /// back for the next Esc and the zoom shortcuts.
  void _onSearchFocus() {
    if (!mounted ||
        _searchFocus.hasFocus ||
        !_searchOpen ||
        _searchController.text.isNotEmpty) {
      return;
    }
    setState(() {
      _searchOpen = false;
      _query = '';
    });
    _canvasFocus.requestFocus();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final depth = widget.neighbourhoodDepth;
      final focus = widget.focusTable;
      final schema = depth != null && focus != null
          ? await widget.source.loadNeighbourhood(focus, depth: depth)
          : await widget.source.loadSchema();
      final saved = await _readSaved(schema);
      if (!mounted) return;
      setState(() {
        _schema = schema;
        _neighbours = _neighbourMap(schema);
        if (saved != null) {
          _collapsed
            ..clear()
            ..addAll(saved.collapsed);
          _hidden
            ..clear()
            ..addAll(saved.hidden);
          _keysOnly = saved.keysOnly;
          _headerColors
            ..clear()
            ..addAll(saved.headerColors);
        }
        _setLayout(
            _withSaved(ErdLayout.compute(_visibleOf(schema)), saved));
        _loading = false;
      });
      if (schema.truncated) {
        showAppToast(
          context: context,
          message: 'The catalog has more than '
              '${ErdCatalog.catalogRowLimit} rows: some tables or columns '
              'are not in the diagram.',
        );
      }
      // The viewport is measured after this frame: fit the diagram, then pick
      // and centre the focused table.
      material.WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scale = saved?.scale;
        final translation = saved?.translation;
        if (scale != null && translation != null) {
          _restoring = true;
          _transform.value = Matrix4.identity()
            ..translate(translation.dx, translation.dy)
            ..scale(scale);
          _restoring = false;
        } else {
          _fit();
        }
        final picked = _focusIn(schema);
        if (picked != null) _selectTable(_visibleOf(schema), picked);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<ErdSavedLayout?> _readSaved(ErdSchema schema) async {
    if (!_persists) return null;
    try {
      final saved = await widget.layoutStore!.read(widget.layoutKey!);
      return saved?.keepOnly({for (final t in schema.tables) t.name});
    } catch (_) {
      return null; // A broken saved layout must not keep the diagram away.
    }
  }

  /// [computed] with the saved cards back where the user left them. Tables
  /// the saved layout does not know (new in the database) keep their computed
  /// arrangement, moved right of the saved cards so nothing overlaps.
  ErdLayout _withSaved(ErdLayout computed, ErdSavedLayout? saved) {
    if (saved == null || saved.positions.isEmpty) return computed;
    var layout = computed;
    var savedRight = 0.0;
    double? newLeft;
    for (final e in computed.positions.entries) {
      final p = saved.positions[e.key];
      if (p != null) {
        savedRight = max(savedRight, p.dx + computed.widthFor(e.key));
      } else {
        newLeft = newLeft == null ? e.value.dx : min(newLeft, e.value.dx);
      }
    }
    final shift = newLeft == null
        ? 0.0
        : savedRight + ErdLayout.layerGap - newLeft;
    for (final e in computed.positions.entries) {
      final p = saved.positions[e.key];
      layout = layout.withPosition(
          e.key, p ?? e.value.translate(shift, 0));
    }
    return layout;
  }

  /// Saves the layout once the changes pause.
  void _scheduleSave() {
    if (!_persists || _restoring || _schema == null || _layout == null) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_saveNow());
    });
  }

  Future<void> _saveNow() async {
    final layout = _layout;
    if (!_persists || layout == null) return;
    final m = _transform.value;
    final t = m.getTranslation();
    try {
      await widget.layoutStore!.write(
        widget.layoutKey!,
        ErdSavedLayout(
          positions: Map.of(layout.positions),
          collapsed: Set.of(_collapsed),
          hidden: Set.of(_hidden),
          keysOnly: _keysOnly,
          headerColors: Map.of(_headerColors),
          scale: m.getMaxScaleOnAxis(),
          translation: material.Offset(t.x, t.y),
        ),
      );
    } catch (_) {
      // Keeping the layout is a convenience: a failed write is not an error
      // the user can act on.
    }
  }

  void _setLayout(ErdLayout layout) {
    _layout = layout;
    final schema = _schema;
    _routes = schema == null
        ? const []
        : ErdRouter.route(_visibleOf(schema), layout);
  }

  /// The focused table as named in [schema]: `public.orders` falls back to
  /// `orders` when the current schema names it without a prefix.
  String? _focusIn(ErdSchema schema) {
    final f = widget.focusTable;
    if (f == null) return null;
    if (schema.tables.any((t) => t.name == f)) return f;
    final bare = f.contains('.') ? f.substring(f.indexOf('.') + 1) : f;
    return schema.tables.any((t) => t.name == bare) ? bare : null;
  }

  /// The schema as drawn: hidden tables gone, columns cut to keys in keys-only
  /// mode, and collapsed cards without columns.
  ErdSchema _visibleOf(ErdSchema schema) {
    final tables = [
      for (final t in schema.tables)
        if (!_hidden.contains(t.name))
          ErdTable(
            name: t.name,
            columns: _collapsed.contains(t.name)
                ? const []
                : [
                    for (final c in t.columns)
                      if (!_keysOnly || c.isPrimaryKey || c.isForeignKey) c,
                  ],
          ),
    ];
    final names = {for (final t in tables) t.name};
    return ErdSchema(
      tables: tables,
      relations: [
        for (final r in schema.relations)
          if (names.contains(r.fromTable) && names.contains(r.toTable)) r,
      ],
    );
  }

  /// Recomputes the layout for the current density and visibility.
  ///
  /// The cards stay where they are unless [arrange]: collapsing, hiding or
  /// showing keys only must not throw away what the user arranged. Only
  /// *Auto layout* computes every position again.
  void _reflow({bool arrange = false}) {
    final schema = _schema;
    if (schema == null) return;
    final computed = ErdLayout.compute(_visibleOf(schema));
    final current = _layout;
    setState(() => _setLayout(arrange || current == null
        ? computed
        : _withSaved(computed, ErdSavedLayout(positions: current.positions))));
    _scheduleSave();
  }

  void _autoLayout() => _reflow(arrange: true);

  void _toggleCollapsed(String table) {
    setState(() {
      if (!_collapsed.remove(table)) _collapsed.add(table);
    });
    _reflow();
  }

  void _hide(String table) {
    setState(() {
      _hidden.add(table);
      // A pick on a hidden table would leave every card faded.
      if (_selected == table) _selected = null;
    });
    _syncFocus();
    _reflow();
  }

  void _showAllTables() {
    setState(_hidden.clear);
    _reflow();
  }

  void _dragStart(String table) {
    setState(() => _dragging = table);
    _syncFocus();
  }

  /// [screenDelta] is in screen pixels; the canvas may be zoomed.
  void _dragMove(String table, material.Offset screenDelta) {
    final layout = _layout;
    if (_dragging != table || layout == null) return;
    final scale = _transform.value.getMaxScaleOnAxis();
    final delta = screenDelta / (scale == 0 ? 1 : scale);
    // The card follows the pointer at once; the edges are routed once per frame.
    setState(() =>
        _layout = layout.withPosition(table, layout.positions[table]! + delta));
    _scheduleRoutes();
  }

  /// Routes the edges once after the current frame, however many pointer
  /// moves came before it.
  void _scheduleRoutes() {
    if (_routeScheduled) return;
    _routeScheduled = true;
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeScheduled = false;
      final schema = _schema;
      final layout = _layout;
      if (!mounted || schema == null || layout == null) return;
      setState(() => _routes = ErdRouter.route(_visibleOf(schema), layout));
    });
  }

  void _dragEnd() {
    if (_dragging == null) return;
    setState(() => _dragging = null);
    _syncFocus();
    _scheduleSave();
  }

  Future<void> _save(String name, Uint8List bytes) =>
      (widget.onSaveFile ?? defaultErdFileSaver)(name, bytes);

  /// The table whose relations are highlighted: the one being dragged, then
  /// the picked one, then the one under the mouse.

  double get _scale => _transform.value.getMaxScaleOnAxis();

  /// Size of the diagram viewport, once it has been laid out.
  material.Size? _viewportSize() {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box.size : null;
  }

  /// Sets the zoom to [target], keeping the scene point under [focal] still.
  void _setScale(double target, material.Offset focal) {
    final s = target.clamp(_zoomFloor, _maxScale).toDouble();
    final t = _transform.value.getTranslation();
    final current = material.Offset(t.x, t.y);
    final next = focal - (focal - current) * (s / _scale);
    _transform.value = Matrix4.identity()..translate(next.dx, next.dy)..scale(s);
  }

  void _zoomBy(double factor) {
    final vs = _viewportSize();
    if (vs == null) return;
    _setScale(_scale * factor, vs.center(material.Offset.zero));
  }

  /// Fits the whole diagram into the viewport, centred, never enlarged.
  void _fit() {
    final layout = _layout;
    final vs = _viewportSize();
    if (layout == null || vs == null) return;
    final s = ErdLayout.fitScale(layout.size, vs);
    final floor = min(_minScale, s);
    if (floor != _zoomFloor) setState(() => _zoomFloor = floor);
    final tx = (vs.width - layout.size.width * s) / 2;
    final ty = (vs.height - layout.size.height * s) / 2;
    _transform.value = Matrix4.identity()..translate(tx, ty)..scale(s);
  }

  /// Picks a table from the search: centres it, closes the search and gives
  /// the keyboard back to the canvas, so Esc then clears the pick.
  void _pickFromSearch(ErdSchema schema, String name) {
    _selectTable(schema, name);
    _searchController.clear();
    setState(() {
      _searchOpen = false;
      _query = '';
    });
    _canvasFocus.requestFocus();
  }

  /// Picks a table and centres the view on it, keeping the zoom.
  void _selectTable(ErdSchema schema, String name) {
    final layout = _layout;
    final vs = _viewportSize();
    final table = schema.tables.firstWhere((t) => t.name == name);
    if (layout != null && vs != null) {
      final p = layout.positions[name]!;
      final centre = material.Offset(p.dx + layout.widthFor(name) / 2,
          p.dy + ErdLayout.cardHeight(table) / 2);
      final s = _scale;
      final t = vs.center(material.Offset.zero) - centre * s;
      _transform.value = Matrix4.identity()..translate(t.dx, t.dy)..scale(s);
    }
    setState(() => _selected = name);
    _syncFocus();
  }

  /// A click on the empty canvas: clears the pick and takes the keyboard, so
  /// the zoom and search shortcuts work after a click anywhere on it.
  void _clearSelection() {
    _canvasFocus.requestFocus();
    if (_selected == null) return;
    setState(() => _selected = null);
    _syncFocus();
  }

  /// A click on a card picks it.
  void _pick(String name) {
    _canvasFocus.requestFocus();
    setState(() => _selected = name);
    _syncFocus();
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    material.WidgetsBinding.instance
        .addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  /// Escape: closes the search when it is open, else clears the pick. One
  /// Esc never does both, so closing the search keeps the table found.
  void _escape() {
    if (_searchOpen) {
      _searchController.clear();
      setState(() {
        _searchOpen = false;
        _query = '';
      });
      _canvasFocus.requestFocus();
      return;
    }
    if (_selected != null) {
      setState(() => _selected = null);
      _syncFocus();
    }
  }

  List<ErdTable> _matches(ErdSchema schema) {
    final q = _query.toLowerCase();
    return [
      for (final t in schema.tables)
        if (t.name.toLowerCase().contains(q)) t,
    ].take(8).toList();
  }

  /// Keyboard shortcuts for both Ctrl (Linux, Windows) and Cmd (macOS).
  Map<material.ShortcutActivator, material.VoidCallback> _bindings() {
    final out = <material.ShortcutActivator, material.VoidCallback>{};
    void both(LogicalKeyboardKey key, material.VoidCallback action,
        {bool shift = false}) {
      out[material.SingleActivator(key, control: true, shift: shift)] = action;
      out[material.SingleActivator(key, meta: true, shift: shift)] = action;
    }

    both(LogicalKeyboardKey.equal, () => _zoomBy(_zoomStep));
    // "+" is Shift+= on most layouts.
    both(LogicalKeyboardKey.equal, () => _zoomBy(_zoomStep), shift: true);
    both(LogicalKeyboardKey.add, () => _zoomBy(_zoomStep));
    both(LogicalKeyboardKey.numpadAdd, () => _zoomBy(_zoomStep));
    both(LogicalKeyboardKey.minus, () => _zoomBy(1 / _zoomStep));
    both(LogicalKeyboardKey.numpadSubtract, () => _zoomBy(1 / _zoomStep));
    both(LogicalKeyboardKey.digit0, _fit);
    both(LogicalKeyboardKey.keyF, _openSearch);
    out[const material.SingleActivator(LogicalKeyboardKey.escape)] = _escape;
    return out;
  }

  /// Tables related to each table by a foreign key, either way. Built once per
  /// build, so the focus test is a set lookup per card.
  static Map<String, Set<String>> _neighbourMap(ErdSchema schema) {
    final out = <String, Set<String>>{};
    for (final r in schema.relations) {
      out.putIfAbsent(r.fromTable, () => {}).add(r.toTable);
      out.putIfAbsent(r.toTable, () => {}).add(r.fromTable);
    }
    return out;
  }

  /// Whether [table] is the focus or related to it.
  static bool _isFocusedIn(
    Map<String, Set<String>> neighbours,
    String? focus,
    String table,
  ) {
    if (focus == null) return false;
    return focus == table || (neighbours[focus]?.contains(table) ?? false);
  }

  /// The table the diagram focuses: the dragged one, then the picked one, then
  /// the one under the mouse.
  String? _currentFocus() => _dragging ?? _selected ?? _hovered.value;

  _CardFocus _cardFocusFor(String table, String? focus) {
    final highlighted = _isFocusedIn(_neighbours, focus, table);
    return (highlighted: highlighted, faded: _selected != null && !highlighted);
  }

  /// The notifier of card [table], made on first use with its current focus.
  material.ValueNotifier<_CardFocus> _cardState(String table) =>
      _cardStates.putIfAbsent(
        table,
        () => material.ValueNotifier(_cardFocusFor(table, _currentFocus())),
      );

  /// Pushes the focus to the edges and to each card. A notifier only fires
  /// when its own highlight or fade changed, so the rest are not rebuilt.
  /// Call after any change to [_selected], [_dragging] or [_hovered].
  void _syncFocus() {
    final focus = _currentFocus();
    _focus.value = focus;
    for (final entry in _cardStates.entries) {
      entry.value.value = _cardFocusFor(entry.key, focus);
    }
  }

  /// PNG of the diagram. With the light palette it is drawn from the same SVG
  /// the SVG export saves, so the two match. With the current theme it is a
  /// screenshot of the canvas: a picked table, the hover highlight and the edge
  /// label are cleared for the capture, and the pick comes back afterwards.
  Future<void> _exportPng(ErdSchema schema, ErdLayout layout) async {
    final currentTheme = await AppSettings.instance.getExportCurrentTheme();
    if (!mounted) return;
    if (!currentTheme) {
      final scale = ErdExport.pngPixelRatio(layout.size);
      final svg = ErdExport.toSvg(schema, layout,
          routes: _routes,
          headerFills: _headerFills(schema, const ErdSvgColors().card));
      await _save('$_fileStem.png', await svgToPng(svg, scale: scale));
      return;
    }
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    final picked = _selected;
    final needsFrame = picked != null ||
        _hovered.value != null ||
        _edgeTipNotifier.value != null;
    _hovered.value = null;
    _edgeTipNotifier.value = null;
    if (picked != null) {
      setState(() => _selected = null);
      _syncFocus();
    }
    try {
      if (needsFrame) await material.WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final ratio = ErdExport.pngPixelRatio(boundary.size);
      if (ratio < 1) {
        showAppToast(
          context: context,
          message: 'The diagram is larger than '
              '${ErdExport.pngMaxSide} px per side, so the PNG is at '
              '${(ratio * 100).round()}% resolution. The SVG export keeps full detail.',
        );
      }
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('no image data');
      await _save('$_fileStem.png', data.buffer.asUint8List());
    } catch (e) {
      if (mounted) {
        showAppToast(
          context: context,
          variant: AppToastVariant.error,
          message: 'Could not render the PNG ($e). '
              'Export SVG instead: it has no size limit.',
        );
      }
    } finally {
      if (mounted && picked != null && _selected == null) {
        setState(() => _selected = picked);
        _syncFocus();
      }
    }
  }

  /// The SVG export: the light palette for documents, unless the setting asks
  /// for the current theme.
  Future<void> _exportSvg(ErdSchema schema, ErdLayout layout) async {
    final currentTheme = await AppSettings.instance.getExportCurrentTheme();
    if (!mounted) return;
    final colors = currentTheme ? _svgColors() : const ErdSvgColors();
    await _save(
        '$_fileStem.svg',
        Uint8List.fromList(utf8.encode(ErdExport.toSvg(schema, layout,
            routes: _routes,
            colors: colors,
            headerFills: _headerFills(schema, colors.card)))));
  }

  /// Flips between the light export palette and the current theme.
  Future<void> _toggleExportTheme() async {
    final now = !await AppSettings.instance.getExportCurrentTheme();
    await AppSettings.instance.setExportCurrentTheme(now);
    if (!mounted) return;
    showAppToast(
      context: context,
      message: now
          ? 'Exports use the current theme'
          : 'Exports use the light palette for documents',
    );
  }

  /// Header colour of [table] on screen: the picked slot, the schema's slot,
  /// or the accent for a table of the current schema.
  material.Color _headerColor(String table) {
    final slot = erdHeaderSlot(table, _headerColors);
    if (slot == null) return context.workbench.accent;
    return _slotColor(slot);
  }

  material.Color _slotColor(String slot) {
    final p = context.semanticPalette;
    return switch (slot) {
      'type1' => p.type1,
      'type2' => p.type2,
      'type3' => p.type3,
      'type4' => p.type4,
      _ => p.type5,
    };
  }

  void _setHeaderColor(String table, String? slot) {
    setState(() {
      if (slot == null) {
        _headerColors.remove(table);
      } else {
        _headerColors[table] = slot;
      }
    });
    _scheduleSave();
  }

  /// Header bands for the SVG: the screen's tint over the export's card colour.
  Map<String, String> _headerFills(ErdSchema schema, String cardHex) {
    final card = material.Color(
        0xFF000000 | int.parse(cardHex.substring(1), radix: 16));
    return {
      for (final t in schema.tables)
        if (erdHeaderSlot(t.name, _headerColors) != null)
          t.name: ErdSvgColors.hex(material.Color.alphaBlend(
                  _headerColor(t.name).withValues(alpha: 0.14), card)
              .toARGB32()),
    };
  }

  /// Colours of the current theme for the SVG export, as the screen draws the
  /// cards and edges.
  ErdSvgColors _svgColors() {
    final wb = context.workbench;
    final palette = context.semanticPalette;
    String hex(material.Color c) => ErdSvgColors.hex(c.toARGB32());
    return ErdSvgColors(
      background: hex(wb.surface),
      card: hex(wb.surface),
      border: hex(wb.borderSubtle),
      header: hex(material.Color.alphaBlend(
          wb.accent.withValues(alpha: 0.10), wb.surface)),
      text: hex(Theme.of(context).colorScheme.foreground),
      muted: hex(wb.mutedForeground),
      edge: hex(wb.mutedForeground),
      primaryKey: hex(palette.type1),
      foreignKey: hex(palette.type2),
    );
  }

  /// `<database>-erd`, or `erd` when the database name is unknown.
  String get _fileStem =>
      widget.databaseName.isEmpty ? 'erd' : '${widget.databaseName}-erd';

  void _export(_ExportAction action, ErdSchema schema, ErdLayout layout) {
    switch (action) {
      case _ExportAction.mermaid:
        _save(
            '$_fileStem.mmd',
            Uint8List.fromList(utf8.encode(ErdExport.toMermaid(schema))));
      case _ExportAction.svg:
        unawaited(_exportSvg(schema, layout));
      case _ExportAction.png:
        unawaited(_exportPng(schema, layout));
      case _ExportAction.toggleTheme:
        unawaited(_toggleExportTheme());
      case _ExportAction.copyMermaid:
        Clipboard.setData(ClipboardData(text: ErdExport.toMermaid(schema)));
        showAppToast(
          context: context,
          message: 'Mermaid copied to the clipboard',
        );
    }
  }

  /// Pointer over the canvas ([p] in canvas space): names the relation within
  /// 6 screen px of it, if any, whatever the zoom.
  void _hoverCanvas(material.Offset p) {
    ErdRelation? hit;
    final scale = _scale;
    var best = 6.0 / (scale <= 0 ? 1 : scale);
    for (final r in _routes) {
      final d = ErdGeometry.distanceToRoute(r.points, p);
      if (d <= best) {
        best = d;
        hit = r.relation;
      }
    }
    // Only the tip layer listens: no rebuild of the view for a hover move.
    _edgeTipNotifier.value = hit == null ? null : (hit, p);
  }

  void _leaveCanvas() => _edgeTipNotifier.value = null;

  /// "orders.customer_id → customers.id" next to the pointer.
  material.Widget _edgeTipLabel(material.BuildContext context, ErdRelation r) {
    final cs = Theme.of(context).colorScheme;
    return material.DecoratedBox(
      decoration: material.BoxDecoration(
        color: cs.popover,
        borderRadius: material.BorderRadius.circular(6),
        border: material.Border.all(color: cs.border),
      ),
      child: material.Padding(
        padding:
            const material.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: material.Text(
          '${r.fromTable}.${r.fromColumn} → ${r.toTable}.${r.toColumn}',
          style: material.TextStyle(
              fontSize: 11, color: cs.popoverForeground),
        ),
      ),
    );
  }

  /// Find-a-table field and the tables it matches. Enter picks the first.
  material.Widget _searchPanel(ErdSchema schema) {
    if (!_searchOpen) return const material.SizedBox.shrink();
    final wb = context.workbench;
    final matches = _matches(schema);
    return material.Column(
      mainAxisSize: material.MainAxisSize.min,
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        QueryaSearchField(
          controller: _searchController,
          focusNode: _searchFocus,
          placeholder: 'Find table',
          debounceDuration: Duration.zero,
          onChanged: (v) => setState(() => _query = v.trim()),
          onSubmitted: (_) {
            if (matches.isNotEmpty) _pickFromSearch(schema, matches.first.name);
          },
        ),
        if (_query.isNotEmpty)
          material.Container(
            margin: const material.EdgeInsets.only(top: 4),
            decoration: material.BoxDecoration(
              color: wb.surface,
              borderRadius: material.BorderRadius.circular(8),
              border: material.Border.all(color: wb.borderSubtle),
            ),
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                if (matches.isEmpty)
                  material.Padding(
                    padding: const material.EdgeInsets.all(8),
                    child: const Text('No tables match').muted().small(),
                  ),
                for (final t in matches)
                  material.GestureDetector(
                    key: material.ValueKey('erd_search_result_${t.name}'),
                    behavior: material.HitTestBehavior.opaque,
                    onTap: () => _pickFromSearch(schema, t.name),
                    child: material.Padding(
                      padding: const material.EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: material.Text(t.name,
                          style: const material.TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    final full = _schema;
    final schema = full == null ? null : _visibleOf(full);
    final layout = _layout;
    material.Widget body;
    if (_loading) {
      body = const material.Center(
          child: QueryaSpinner(label: 'Loading schema…'));
    } else if (_error != null) {
      body = material.Center(
        child: QueryaEmptyState(
          icon: material.Icon(material.Icons.error_outline_rounded,
              color: wb.destructive),
          title: 'Could not load the schema',
          description: _error,
          actionLabel: 'Retry',
          onAction: _load,
        ),
      );
    } else if (full != null && full.tables.isNotEmpty && schema!.isEmpty) {
      // Every table was hidden from the diagram: they exist, so say so and
      // offer them back instead of "No tables found".
      body = material.Center(
        child: QueryaEmptyState(
          icon: material.Icon(material.Icons.visibility_off_outlined,
              color: wb.mutedForeground),
          title: 'All tables are hidden',
          description: '${_hidden.length} '
              '${_hidden.length == 1 ? 'table is' : 'tables are'} hidden '
              'from the diagram.',
          actionLabel: 'Show all tables',
          onAction: _showAllTables,
        ),
      );
    } else if (schema == null || layout == null || schema.isEmpty) {
      final db = widget.databaseName;
      body = material.Center(
        child: QueryaEmptyState(
          icon: material.Icon(material.Icons.table_chart_outlined,
              color: wb.mutedForeground),
          title: 'No tables found',
          description: db.isEmpty
              ? 'This schema has no tables, or this role cannot see them.'
              : 'The current schema of $db has no tables, or this role '
                  'cannot see them.',
        ),
      );
    } else if (widget.neighbourhoodDepth != null &&
        widget.focusTable != null &&
        schema.relations.isEmpty) {
      body = material.Center(
        child: QueryaEmptyState(
          icon: material.Icon(material.Icons.link_off_rounded,
              color: wb.mutedForeground),
          title: 'No foreign keys to or from ${widget.focusTable}',
          description: 'This table has no relations within the schema.',
          actionLabel: 'Open full diagram',
          onAction: widget.onOpenFullDiagram,
        ),
      );
    } else {
      body = material.CallbackShortcuts(
        bindings: _bindings(),
        child: material.Focus(
          focusNode: _canvasFocus,
          autofocus: true,
          child: material.Stack(
            key: _viewportKey,
            children: [
              material.InteractiveViewer(
                constrained: false,
                transformationController: _transform,
                // A card drag must not pan the canvas.
                panEnabled: _dragging == null,
                minScale: _zoomFloor,
                maxScale: _maxScale,
                boundaryMargin: const material.EdgeInsets.all(400),
                child: material.RepaintBoundary(
                  key: _boundaryKey,
                  child: material.Container(
                    color: wb.surface,
                    width: layout.size.width,
                    height: layout.size.height,
                    child: material.GestureDetector(
                      // Empty canvas: a tap clears the selection.
                      behavior: material.HitTestBehavior.translucent,
                      onTap: _clearSelection,
                      child: material.Stack(
                        children: [
                          // Lowest layer: sees the pointer wherever no card is,
                          // so edges can name themselves on hover.
                          material.Positioned.fill(
                            child: material.MouseRegion(
                              opaque: false,
                              onHover: (e) => _hoverCanvas(e.localPosition),
                              onExit: (_) => _leaveCanvas(),
                              child: const material.SizedBox.expand(),
                            ),
                          ),
                          material.Positioned.fill(
                            child: material.ValueListenableBuilder<String?>(
                              valueListenable: _focus,
                              builder: (context, focus, _) =>
                                  material.CustomPaint(
                                painter: _RelationPainter(
                                  routes: _routes,
                                  color: wb.mutedForeground,
                                  highlight: wb.accent,
                                  focus: focus,
                                ),
                              ),
                            ),
                          ),
                          for (final t in schema.tables)
                            material.Positioned(
                              left: layout.positions[t.name]!.dx,
                              top: layout.positions[t.name]!.dy,
                              // Each card listens to its own focus, so a hover
                              // rebuilds only the cards it changes.
                              child: material.ValueListenableBuilder<_CardFocus>(
                                valueListenable: _cardState(t.name),
                                builder: (context, focus, _) => material.Opacity(
                                  // Unrelated cards fade while a table is picked.
                                  opacity: focus.faded ? 0.35 : 1,
                                  child: ContextMenu(
                                  items: [
                                    if (widget.onOpenTable case final open?)
                                      MenuButton(
                                        key: material.ValueKey(
                                            'erd_menu_open_${t.name}'),
                                        onPressed: (_) => open(t.name),
                                        child: const Text('Open data'),
                                      ),
                                    if (widget.onOpenInSql case final inSql?)
                                      MenuButton(
                                        key: material.ValueKey(
                                            'erd_menu_sql_${t.name}'),
                                        onPressed: (_) => inSql(t.name),
                                        child: const Text('Open in SQL'),
                                      ),
                                    if (widget.onShowRelations
                                        case final relations?)
                                      MenuButton(
                                        key: material.ValueKey(
                                            'erd_menu_relations_${t.name}'),
                                        onPressed: (_) => relations(t.name),
                                        child: const Text('Show relations'),
                                      ),
                                    MenuButton(
                                      onPressed: (_) {
                                        Clipboard.setData(
                                            ClipboardData(text: t.name));
                                      },
                                      child: const Text('Copy name'),
                                    ),
                                    MenuButton(
                                      onPressed: (_) => _toggleCollapsed(t.name),
                                      child: Text(_collapsed.contains(t.name)
                                          ? 'Expand'
                                          : 'Collapse'),
                                    ),
                                    MenuButton(
                                      onPressed: (_) => _hide(t.name),
                                      child: const Text('Hide from diagram'),
                                    ),
                                    MenuButton(
                                      key: material.ValueKey(
                                          'erd_menu_colour_${t.name}'),
                                      subMenu: [
                                        MenuButton(
                                          onPressed: (_) =>
                                              _setHeaderColor(t.name, null),
                                          child: const Text('Default'),
                                        ),
                                        for (var i = 0;
                                            i < erdHeaderSlots.length;
                                            i++)
                                          MenuButton(
                                            leading: material.Icon(
                                              material.Icons.circle,
                                              size: 12,
                                              color: _slotColor(
                                                  erdHeaderSlots[i]),
                                            ),
                                            onPressed: (_) => _setHeaderColor(
                                                t.name, erdHeaderSlots[i]),
                                            child: Text('Colour ${i + 1}'),
                                          ),
                                      ],
                                      child: const Text('Header colour'),
                                    ),
                                  ],
                                  child: _TableCard(
                                  table: t,
                                  width: layout.widthFor(t.name),
                                  headerColor: _headerColor(t.name),
                                  highlighted: focus.highlighted,
                                  dragging: _dragging == t.name,
                                  onOpen: widget.onOpenTable == null
                                      ? null
                                      : () => widget.onOpenTable!(t.name),
                                  onSelect: () => _pick(t.name),
                                  onHover: (inside) => _hovered.value = inside
                                      ? t.name
                                      : (_hovered.value == t.name
                                          ? null
                                          : _hovered.value),
                                  onDragStart: () => _dragStart(t.name),
                                  onDragMove: (d) => _dragMove(t.name, d),
                                  onDragEnd: _dragEnd,
                                ),
                                ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // The edge label sits above the zoomed canvas, in screen space,
              // so it stays readable at any zoom and is never in a PNG.
              material.Positioned.fill(
                child: material.IgnorePointer(
                  child: material.ListenableBuilder(
                    listenable: material.Listenable.merge(
                        [_edgeTipNotifier, _transform]),
                    builder: (context, _) {
                      final tip = _edgeTipNotifier.value;
                      if (tip == null) return const material.SizedBox.shrink();
                      final at = material.MatrixUtils.transformPoint(
                          _transform.value, tip.$2);
                      return material.Stack(
                        children: [
                          material.Positioned(
                            key: const material.ValueKey('erd_edge_tip'),
                            left: at.dx + 12,
                            top: at.dy + 12,
                            child: _edgeTipLabel(context, tip.$1),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              material.Positioned(
                left: 8,
                top: 8,
                width: 260,
                child: _searchPanel(schema),
              ),
              material.Positioned(
                right: 8,
                bottom: 8,
                child: material.ValueListenableBuilder<Matrix4>(
                  valueListenable: _transform,
                  builder: (context, m, _) => ErdZoomControls(
                    scale: m.getMaxScaleOnAxis(),
                    onZoomIn: () => _zoomBy(_zoomStep),
                    onZoomOut: () => _zoomBy(1 / _zoomStep),
                    onFit: _fit,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final ready = schema != null && layout != null && !schema.isEmpty;
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Container(
          decoration: SqlEditorChrome.sqlToolbarDecoration(context),
          padding: const material.EdgeInsets.all(8),
          child: material.Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: material.WrapCrossAlignment.center,
            children: [
              QueryaActionButton(
                key: const material.ValueKey('erd_refresh'),
                label: 'Refresh',
                icon: material.Icons.refresh_rounded,
                onPressed: _loading ? null : _load,
              ),
              QueryaActionButton(
                key: const material.ValueKey('erd_keys_only'),
                label: _keysOnly ? 'All columns' : 'Keys only',
                icon: material.Icons.key_rounded,
                tooltip: 'Show only primary and foreign keys',
                onPressed: !ready
                    ? null
                    : () {
                        setState(() => _keysOnly = !_keysOnly);
                        _reflow();
                      },
              ),
              if (_hidden.isNotEmpty)
                QueryaActionButton(
                  key: const material.ValueKey('erd_show_all'),
                  label: 'Show ${_hidden.length} hidden',
                  icon: material.Icons.visibility_outlined,
                  onPressed: _showAllTables,
                ),
              QueryaActionButton(
                key: const material.ValueKey('erd_auto_layout'),
                label: 'Auto layout',
                icon: material.Icons.auto_fix_high_rounded,
                tooltip: 'Arrange the tables again (undoes manual moves)',
                onPressed: ready ? _autoLayout : null,
              ),
              material.IgnorePointer(
                ignoring: !ready,
                child: material.Opacity(
                  opacity: ready ? 1 : 0.5,
                  child: QueryaActionMenu<_ExportAction>(
                    items: const [
                      QueryaActionMenuItem(
                        value: _ExportAction.toggleTheme,
                        label: 'Toggle export theme (light / current)',
                        icon: material.Icons.palette_outlined,
                      ),
                      QueryaActionMenuItem(
                        value: _ExportAction.mermaid,
                        label: 'Mermaid (.mmd)',
                        icon: material.Icons.account_tree_outlined,
                      ),
                      QueryaActionMenuItem(
                        value: _ExportAction.svg,
                        label: 'SVG',
                        icon: material.Icons.polyline_outlined,
                      ),
                      QueryaActionMenuItem(
                        value: _ExportAction.png,
                        label: 'PNG',
                        icon: material.Icons.image_outlined,
                      ),
                      QueryaActionMenuItem(
                        value: _ExportAction.copyMermaid,
                        label: 'Copy Mermaid',
                        icon: material.Icons.content_copy_rounded,
                      ),
                    ],
                    onSelected: (action) {
                      if (schema != null && layout != null) {
                        _export(action, schema, layout);
                      }
                    },
                    child: material.Padding(
                      key: const material.ValueKey('erd_export'),
                      padding: const material.EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: material.Row(
                        mainAxisSize: material.MainAxisSize.min,
                        children: [
                          material.Icon(material.Icons.file_download_outlined,
                              size: 16, color: wb.mutedForeground),
                          const material.SizedBox(width: 6),
                          const Text('Export'),
                          const material.SizedBox(width: 4),
                          material.Icon(material.Icons.expand_more_rounded,
                              size: 16, color: wb.mutedForeground),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        material.Expanded(child: material.ClipRect(child: body)),
      ],
    );
  }
}

class _TableCard extends material.StatelessWidget {
  const _TableCard({
    required this.table,
    required this.width,
    required this.headerColor,
    required this.highlighted,
    required this.dragging,
    required this.onHover,
    required this.onDragStart,
    required this.onDragMove,
    required this.onDragEnd,
    this.onOpen,
    this.onSelect,
  });

  final ErdTable table;

  /// From the layout: sized to the card's content (#1276).
  final double width;

  /// Header tint and icon: by schema, picked per table, or the accent.
  final material.Color headerColor;
  final bool highlighted;
  final bool dragging;
  final material.VoidCallback? onOpen;
  final material.VoidCallback? onSelect;
  final void Function(bool inside) onHover;
  final material.VoidCallback onDragStart;
  final void Function(material.Offset delta) onDragMove;
  final material.VoidCallback onDragEnd;

  /// Shadows read only on light surfaces, so a dark canvas gets twice the alpha.
  double _shadowAlpha(material.Color canvas) {
    final base = dragging ? 0.28 : 0.12;
    return canvas.computeLuminance() < 0.5 ? base * 2 : base;
  }

  @override
  material.Widget build(material.BuildContext context) {
    erdCardBuilds++;
    final wb = context.workbench;
    final palette = context.semanticPalette;
    final radius = material.BorderRadius.circular(8);
    return material.MouseRegion(
        cursor: dragging
            ? material.SystemMouseCursors.grabbing
            : material.SystemMouseCursors.grab,
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        // The card's pan recognizer joins the arena before the canvas's one
        // and wins it, so dragging a card never pans the canvas. `down`
        // reports the movement from the press, slop included.
        child: material.GestureDetector(
          key: material.ValueKey('erd_table_${table.name}'),
          dragStartBehavior: DragStartBehavior.down,
          onTap: onSelect,
          onDoubleTap: onOpen,
          onPanStart: (_) => onDragStart(),
          onPanUpdate: (d) => onDragMove(d.delta),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragEnd,
          child: material.Container(
            width: width,
            height: ErdLayout.cardHeight(table),
            decoration: material.BoxDecoration(
              color: wb.surface,
              borderRadius: radius,
              border: material.Border.all(
                color: highlighted ? wb.accent : wb.borderSubtle,
                width: highlighted ? 1.5 : 1,
              ),
              boxShadow: [
                material.BoxShadow(
                  color: wb.shadow.withValues(alpha: _shadowAlpha(wb.canvas)),
                  blurRadius: dragging ? 18 : 8,
                  offset: material.Offset(0, dragging ? 6 : 2),
                ),
              ],
            ),
            child: material.ClipRRect(
              borderRadius: radius,
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  material.Container(
                    height: ErdLayout.headerHeight,
                    color: headerColor.withValues(
                        alpha: highlighted ? 0.18 : 0.10),
                    padding: const material.EdgeInsets.symmetric(horizontal: 10),
                    child: material.Row(
                      children: [
                        material.Icon(material.Icons.table_chart_outlined,
                            size: 14, color: headerColor),
                        const material.SizedBox(width: 6),
                        material.Expanded(
                          child: Text(table.name,
                              maxLines: 1,
                              overflow: material.TextOverflow.ellipsis,
                              style: const material.TextStyle(
                                  fontWeight: material.FontWeight.w600,
                                  fontSize: 13)),
                        ),
                        Text('${table.columns.length}',
                            style: material.TextStyle(
                                fontSize: 10, color: wb.mutedForeground)),
                      ],
                    ),
                  ),
                  for (final c in table.columns)
                    material.SizedBox(
                      height: ErdLayout.rowHeight,
                      child: material.Tooltip(
                        message: '${c.name} ${c.type}',
                        child: material.Padding(
                          padding: const material.EdgeInsets.symmetric(
                              horizontal: 10),
                          child: material.Row(
                            children: [
                              // A column can be both PK and FK (junction
                              // tables), so both markers get a slot.
                              material.SizedBox(
                                width: 26,
                                child: material.Row(
                                  mainAxisSize: material.MainAxisSize.min,
                                  children: [
                                    if (c.isPrimaryKey)
                                      material.Icon(material.Icons.key_rounded,
                                          size: 11, color: palette.type1),
                                    if (c.isPrimaryKey && c.isForeignKey)
                                      const material.SizedBox(width: 4),
                                    if (c.isForeignKey)
                                      material.Icon(material.Icons.link_rounded,
                                          size: 11, color: palette.type2),
                                  ],
                                ),
                              ),
                              // The card is sized to fit both; when it hit its
                              // maximum, the name gives way and the type keeps
                              // at most half the row.
                              material.Expanded(
                                child: Text(c.name,
                                    maxLines: 1,
                                    overflow: material.TextOverflow.ellipsis,
                                    style: material.TextStyle(
                                      fontSize: 12,
                                      fontWeight: c.isPrimaryKey
                                          ? material.FontWeight.w600
                                          : material.FontWeight.normal,
                                    )),
                              ),
                              const material.SizedBox(width: 8),
                              material.ConstrainedBox(
                                constraints: material.BoxConstraints(
                                    maxWidth: (width - 56) / 2),
                                child: Text(c.isNullable ? '${c.type}?' : c.type,
                                    maxLines: 1,
                                    overflow: material.TextOverflow.ellipsis,
                                    style: material.TextStyle(
                                        fontSize: 10,
                                        fontFamily: QueryaTypography.mono,
                                        fontFamilyFallback:
                                            QueryaTypography.monoFontFamilyFallback,
                                        color: wb.mutedForeground)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ),
    );
  }
}

class _RelationPainter extends material.CustomPainter {
  _RelationPainter({
    required this.routes,
    required this.color,
    required this.highlight,
    required this.focus,
  });

  final List<ErdRoute> routes;
  final material.Color color;
  final material.Color highlight;

  /// Table whose relations are drawn on top in [highlight].
  final String? focus;

  bool _focused(ErdRoute r) =>
      focus != null &&
      (r.relation.fromTable == focus || r.relation.toTable == focus);

  @override
  void paint(material.Canvas canvas, material.Size size) {
    // Others first, focused on top.
    for (final pass in [false, true]) {
      for (final r in routes) {
        if (_focused(r) != pass || r.points.length < 2) continue;
        final paint = material.Paint()
          ..color = pass ? highlight : color.withValues(alpha: focus == null ? 0.85 : 0.35)
          ..style = material.PaintingStyle.stroke
          ..strokeWidth = pass ? 2 : 1.4
          ..strokeCap = material.StrokeCap.round
          ..strokeJoin = material.StrokeJoin.round;
        canvas.drawPath(roundedPath(r.points), paint);
        for (final (a, b) in ErdGeometry.crowFoot(r.points[0], r.points[1])) {
          canvas.drawLine(a, b, paint);
        }
        // FK side: a circle when the column may be NULL ("zero or many"), a
        // bar otherwise ("one or many").
        if (r.relation.optional) {
          final (c, radius) =
              ErdGeometry.optionalCircle(r.points[0], r.points[1]);
          canvas.drawCircle(c, radius, paint);
        } else {
          final (fa, fb) =
              ErdGeometry.oneBar(r.points[0], r.points[1], distance: 17);
          canvas.drawLine(fa, fb, paint);
        }
        final (barA, barB) =
            ErdGeometry.oneBar(r.points.last, r.points[r.points.length - 2]);
        canvas.drawLine(barA, barB, paint);
      }
    }
  }

  /// Edges take no pointer: a CustomPaint is hit everywhere by default, which
  /// hid the pointer from the hover layer below and so the edge label never
  /// showed.
  @override
  bool? hitTest(material.Offset position) => false;

  @override
  bool shouldRepaint(_RelationPainter old) =>
      old.routes != routes ||
      old.color != color ||
      old.highlight != highlight ||
      old.focus != focus;
}

/// Polyline with corners rounded by up to 8 px.
material.Path roundedPath(List<material.Offset> pts, {double radius = 8}) {
  final path = material.Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final (p1, corner, p2) in ErdGeometry.corners(pts, radius: radius)) {
    path
      ..lineTo(p1.dx, p1.dy)
      ..quadraticBezierTo(corner.dx, corner.dy, p2.dx, p2.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  return path;
}
