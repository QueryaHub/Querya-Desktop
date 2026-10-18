import 'dart:async';
import 'dart:math' show max;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, LogicalKeyboardKey;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/erd/erd_card_measure.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/features/erd/erd_export_data.dart';
import 'package:querya_desktop/features/erd/erd_exporter.dart';
import 'package:querya_desktop/core/erd/erd_geometry.dart';
import 'package:querya_desktop/features/erd/erd_group_dialog.dart';
import 'package:querya_desktop/features/erd/erd_note_dialog.dart';
import 'package:querya_desktop/features/erd/erd_view_controller.dart';
import 'package:querya_desktop/features/erd/erd_viewport.dart';
import 'package:querya_desktop/features/erd/erd_view_name_dialog.dart';
import 'package:querya_desktop/core/erd/erd_group_ops.dart';
import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_layout_engine.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_note_ops.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/core/erd/erd_router.dart';
import 'package:querya_desktop/features/erd/widgets/erd_canvas.dart';
import 'package:querya_desktop/features/erd/widgets/erd_card_cache.dart';
import 'package:querya_desktop/features/erd/widgets/erd_card_inputs.dart';
import 'package:querya_desktop/features/erd/widgets/erd_edge_tip_label.dart';
import 'package:querya_desktop/features/erd/widgets/erd_export_menu.dart';
import 'package:querya_desktop/features/erd/widgets/erd_group_frame.dart';
import 'package:querya_desktop/features/erd/widgets/erd_note_card.dart';
import 'package:querya_desktop/features/erd/widgets/erd_search_panel.dart';
import 'package:querya_desktop/features/erd/widgets/erd_status_body.dart';
import 'package:querya_desktop/features/erd/widgets/erd_group_menu.dart';
import 'package:querya_desktop/features/erd/widgets/erd_table_menu.dart';
import 'package:querya_desktop/features/erd/widgets/erd_toolbar.dart';
import 'package:querya_desktop/features/erd/widgets/erd_views_menu.dart';
import 'package:querya_desktop/features/erd/widgets/erd_table_card.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';
import 'package:querya_desktop/shared/widgets/querya_spinner.dart';
import 'package:querya_desktop/shared/widgets/querya_context_menu.dart';

// Moved out of this file (#1362); re-exported for existing importers.
export 'package:querya_desktop/features/erd/widgets/erd_relation_painter.dart'
    show roundedPath;
export 'package:querya_desktop/features/erd/widgets/erd_table_card.dart'
    show erdCardBuilds;

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

class _ErdViewState extends material.State<ErdView>
    implements ErdExportSource {
  late final ErdExporter _exporter = ErdExporter(this);
  final _c = ErdViewController();

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
  bool _routeScheduled = false;

  /// The focus the edges draw. Every card has its own notifier in
  /// [_cardStates]; [_syncFocus] moves only the ones whose focus changed, so a
  /// hover rebuilds the cards it touches and not the whole canvas.
  final _focus = material.ValueNotifier<String?>(null);
  final _cardStates = <String, material.ValueNotifier<ErdCardFocus>>{};

  /// Density: only PK and FK columns, cards collapsed to their header, and
  /// tables hidden from the diagram. Layout and routing follow the visible
  /// schema from [_visibleOf].

  /// A relation picked by a click on its edge (#1281): its two tables and
  /// columns are highlighted and its label stays until Esc.

  /// Many-to-many link tables and what they link: `users and roles` (#1281).

  /// Header colour picked per table (palette slot names, #1276).

  /// The user's table groups, saved with the layout (#1282).

  /// Tables marked with Shift / Ctrl / Cmd + click, to be grouped.

  /// The group whose frame is being dragged by its title.

  /// Saved views of the diagram (#1284), the one the user is in, and the
  /// *All tables* state while a view is active.

  /// Sticky notes on the canvas, saved with the layout (#1283).

  /// Relation under the pointer and the pointer position in canvas space.
  final _edgeTipNotifier =
      material.ValueNotifier<(ErdRelation, material.Offset)?>(null);

  final _searchController = material.TextEditingController();
  final _searchFocus = material.FocusNode();
  final _canvasFocus = material.FocusNode();
  final _viewport = ErdViewport();

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
    _viewport.transform.removeListener(_scheduleSave);
    _viewport.dispose();
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
    _viewport.transform.addListener(_scheduleSave);
    _load();
  }

  /// The search field handles Esc itself: the first clears the text, the
  /// next drops the focus, so the view's own Esc never sees it. An empty
  /// search that loses the focus closes, and the canvas gets the keyboard
  /// back for the next Esc and the zoom shortcuts.
  void _onSearchFocus() {
    if (!mounted ||
        _searchFocus.hasFocus ||
        !_c.searchOpen ||
        _searchController.text.isNotEmpty) {
      return;
    }
    setState(() {
      _c.searchOpen = false;
      _c.query = '';
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
      final stored = await _readSaved(schema);
      if (!mounted) return;
      // The state to show: the diagram's own, or the view it was left in.
      var saved = stored;
      if (stored != null) {
        _c.base = stored;
        _c.views
          ..clear()
          ..addAll(stored.views);
        _c.activeView = stored.activeView;
        final view = _c.viewById(_c.activeView);
        if (view != null) {
          saved = view.asLayout(
              {for (final t in schema.tables) t.name}, stored.headerColors);
        }
      }
      setState(() {
        _schema = schema;
        _c.neighbours = ErdLayoutEngine.neighbourMap(schema);
        _c.junctions = ErdLayoutEngine.junctionMap(schema);
        _c.pickedRelation = null;
        if (saved != null) _c.applyState(saved, colours: true);
        _c.marked.clear();
        _setLayout(ErdLayoutEngine.withSaved(_compute(_visibleOf(schema)), saved));
        _loading = false;
        _cardCache.reset(schema.tables.length);
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
          _viewport.set(scale: scale, translation: translation);
          _restoring = false;
        } else {
          _fit();
        }
        final picked = ErdLayoutEngine.focusIn(schema, widget.focusTable);
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

  /// Layout with cards measured in this view's fonts and text scale.
  ErdLayout _compute(ErdSchema schema) {
    final measure = ErdCardMeasure(
      base: material.DefaultTextStyle.of(context).style,
      textScaler: material.MediaQuery.textScalerOf(context),
    );
    return ErdLayout.compute(schema,
        measure: measure.width,
        groups: [for (final g in _c.allGroups(_schema)) g.tables]);
  }

  /// Asks for a name and groups [tables], taking them out of other groups.
  Future<void> _newGroup(Set<String> tables) async {
    if (tables.isEmpty) return;
    final n = ErdGroupOps.nextNameNumber(_c.groups);
    final text = await showErdGroupDialog(context,
        title: 'New group', action: 'Create', name: 'Group $n');
    if (text == null || !mounted) return;
    late final String id;
    setState(() {
      id = _c.createGroup(
        tables: tables,
        tableNames: [for (final t in _schema?.tables ?? const <ErdTable>[]) t.name],
        name: text.name,
        note: text.note,
      );
    });
    _gatherIfCovering(id);
    _scheduleSave();
  }

  /// A group frame that would cover other cards: the group's tables are
  /// packed into one block, the other cards stay (#1282).
  void _gatherIfCovering(String id) {
    final layout = _layout;
    final i = _c.groups.indexWhere((g) => g.id == id);
    if (layout == null || i < 0) return;
    final tables = _c.groups[i].tables;
    if (!layout.frameCoversOthers(tables)) return;
    setState(() {
      _setLayout(layout.gather(tables));
      _c.followTables(layout, _layout);
    });
    showAppToast(
      context: context,
      message: 'Moved the tables of "${_c.groups[i].name}" together so its '
          'frame covers no other table.',
    );
  }

  void _addToGroup(String id, Set<String> tables) {
    setState(() => _c.addToGroup(id, tables));
    _gatherIfCovering(id);
    _scheduleSave();
  }

  Future<void> _editGroup(ErdGroup group) async {
    final text = await showErdGroupDialog(context,
        title: 'Edit group',
        action: 'Save',
        name: group.name,
        note: group.note);
    if (text == null || !mounted) return;
    _updateGroup(group.id,
        (g) => g.copyWith(name: text.name, note: () => text.note));
  }

  void _updateGroup(String id, ErdGroup Function(ErdGroup) change) {
    var found = false;
    setState(() => found = _c.updateGroup(id, change));
    if (found) _scheduleSave();
  }

  void _ungroup(String id) {
    setState(() => _c.ungroup(id));
    _scheduleSave();
  }

  void _removeFromGroup(String table) {
    setState(() => _c.removeFromGroup(table));
    _scheduleSave();
  }

  /// A click on a card: with Shift, Ctrl or Cmd it marks or unmarks the table
  /// for a group, otherwise it picks it.
  void _tapCard(String table) {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed || keys.isControlPressed || keys.isMetaPressed) {
      _canvasFocus.requestFocus();
      setState(() => _c.toggleMarked(table));
      return;
    }
    if (_c.marked.isNotEmpty) setState(_c.marked.clear);
    _pick(table);
  }

  /// Applies [target] (a view's state, or the diagram's own) and its
  /// viewport, after the current state was kept where it belongs.
  void _showState(String? viewId, ErdSavedLayout target) {
    final schema = _schema;
    if (schema == null) return;
    setState(() {
      _c.activeView = viewId;
      _c.selected = null;
      _c.pickedRelation = null;
      _c.marked.clear();
      _c.applyState(target, colours: false);
      _setLayout(ErdLayoutEngine.withSaved(_compute(_visibleOf(schema)), target));
    });
    _syncFocus();
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scale = target.scale, translation = target.translation;
      if (scale != null && translation != null) {
        _restoring = true;
        _viewport.set(scale: scale, translation: translation);
        _restoring = false;
      } else {
        _fit();
      }
    });
    _scheduleSave();
  }

  /// Switches to the view [id], or to *All tables* for null.
  void _switchView(String? id) {
    final schema = _schema;
    if (schema == null || id == _c.activeView) return;
    _captureCurrent();
    final target =
        _c.stateOfView(id, {for (final t in schema.tables) t.name});
    if (target != null) _showState(id, target);
  }

  /// Saves what the diagram shows as a new view and moves into it.
  Future<void> _newView() async {
    final schema = _schema;
    if (schema == null) return;
    final name = await showErdViewNameDialog(context,
        title: 'New view',
        action: 'Save',
        name: 'View ${_c.views.length + 1}');
    if (name == null || !mounted) return;
    _captureCurrent();
    setState(() => _c.addViewFromCurrent(
          name: name,
          current: _current(),
          tableNames: [for (final t in schema.tables) t.name],
        ));
    _scheduleSave();
  }

  Future<void> _renameView() async {
    final view = _c.viewById(_c.activeView);
    if (view == null) return;
    final name = await showErdViewNameDialog(context,
        title: 'Rename view', action: 'Rename', name: view.name);
    if (name == null || !mounted) return;
    var found = false;
    setState(() => found = _c.renameView(view.id, name));
    if (found) _scheduleSave();
  }

  /// Deletes the active view and goes back to *All tables*.
  void _deleteView() {
    final id = _c.activeView;
    if (id == null) return;
    _c.removeView(id);
    _showState(null, _c.base);
  }

  Future<void> _addNote() async {
    final text = await showErdNoteDialog(context,
        title: 'New note', action: 'Add');
    if (text == null || !mounted) return;
    final note =
        ErdNoteOps.create(_c.notes, text: text, centre: _viewport.centre());
    setState(() => _c.addNote(note));
    _scheduleSave();
  }

  Future<void> _editNote(ErdNote note) async {
    final text = await showErdNoteDialog(context,
        title: 'Edit note', action: 'Save', text: note.text);
    if (text == null || !mounted) return;
    _updateNote(note.id, (n) => n.copyWith(text: text));
  }

  void _updateNote(String id, ErdNote Function(ErdNote) change) {
    var found = false;
    setState(() => found = _c.updateNote(id, change));
    if (found) _scheduleSave();
  }

  void _deleteNote(String id) {
    setState(() => _c.deleteNote(id));
    _scheduleSave();
  }

  void _noteDragMove(String id, material.Offset screenDelta) {
    setState(() => _c.moveNote(id, screenDelta, _viewport.scale));
  }

  void _noteResize(String id, material.Offset screenDelta) {
    setState(() => _c.resizeNote(id, screenDelta, _viewport.scale));
  }

  /// The table nearest to a note's middle, to attach it to.
  String? _nearestTable(ErdNote n) {
    final layout = _layout;
    final schema = _schema;
    if (layout == null || schema == null) return null;
    return ErdNoteOps.nearestTable(n, layout, _visibleOf(schema));
  }

  /// Tint of a note without a colour over the canvas, on screen and in the
  /// exports.
  static const double _noteTint = 0.07;

  material.Widget _noteWidget(ErdNote n) => ErdNoteCard(
        note: n,
        tint: _noteTint,
        slotColor: _slotColor,
        dragging: _c.draggingNote == n.id,
        onFocusCanvas: _canvasFocus.requestFocus,
        onDragStart: () => setState(() => _c.draggingNote = n.id),
        onDragMove: (d) => _noteDragMove(n.id, d),
        onDragEnd: () {
          setState(() => _c.draggingNote = null);
          _scheduleSave();
        },
        onDragCancel: () => setState(() => _c.draggingNote = null),
        onEdit: () => unawaited(_editNote(n)),
        onChange: (change) => _updateNote(n.id, change),
        onAttachNearest: () {
          final t = _nearestTable(n);
          if (t != null) {
            _updateNote(n.id, (o) => o.copyWith(attachedTo: () => t));
          }
        },
        onDelete: () => _deleteNote(n.id),
        onResize: (d) => _noteResize(n.id, d),
        onResizeEnd: _scheduleSave,
      );

  void _groupDragStart(String id) => setState(() => _c.draggingGroup = id);

  /// Moves every visible table of [group] by [screenDelta], keeping its frame
  /// inside the canvas.
  void _groupDragMove(ErdGroup group, material.Offset screenDelta) {
    final layout = _layout;
    if (_c.draggingGroup != group.id || layout == null) return;
    final frame = layout.frameOf(group.tables);
    if (frame == null) return;
    final scale = _viewport.scale;
    var delta = screenDelta / (scale == 0 ? 1 : scale);
    delta = material.Offset(
        max(delta.dx, -frame.left), max(delta.dy, -frame.top));
    setState(() {
      _layout = layout.withPositions({
        for (final t in group.tables)
          if (layout.positions[t] case final p?) t: p + delta,
      });
      _c.followTables(layout, _layout);
    });
    _scheduleRoutes();
  }

  void _groupDragEnd() {
    if (_c.draggingGroup == null) return;
    setState(() => _c.draggingGroup = null);
    _scheduleSave();
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

  /// What the diagram shows and how it is arranged right now.
  ErdSavedLayout _current() => _c.snapshot(
        positions: _layout?.positions ?? const {},
        scale: _viewport.scale,
        translation: _viewport.translation,
      );

  /// Writes the current state to where it belongs: the active view, or the
  /// diagram's own (*All tables*) state.
  void _captureCurrent() {
    final schema = _schema;
    if (schema == null || _layout == null) return;
    _c.capture(_current(), [for (final t in schema.tables) t.name]);
  }

  Future<void> _saveNow() async {
    final layout = _layout;
    if (!_persists || layout == null) return;
    _captureCurrent();
    try {
      await widget.layoutStore!.write(widget.layoutKey!, _c.toStore());
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

  /// The schema as drawn, for the current density and visibility.
  ErdSchema _visibleOf(ErdSchema schema) => ErdLayoutEngine.visibleOf(
        schema,
        hidden: _c.hidden,
        collapsed: _c.collapsed,
        detail: _c.detail,
      );

  /// Recomputes the layout for the current density and visibility.
  ///
  /// The cards stay where they are unless [arrange]: collapsing, hiding or
  /// showing keys only must not throw away what the user arranged. Only
  /// *Auto layout* computes every position again.
  void _reflow({bool arrange = false}) {
    final schema = _schema;
    if (schema == null) return;
    final computed = _compute(_visibleOf(schema));
    final current = _layout;
    setState(() {
      _setLayout(arrange || current == null
          ? computed
          : ErdLayoutEngine.withSaved(computed, ErdSavedLayout(positions: current.positions)));
      if (current != null) _c.followTables(current, _layout);
    });
    _scheduleSave();
  }

  void _autoLayout() => _reflow(arrange: true);

  void _toggleCollapsed(String table) {
    setState(() => _c.toggleCollapsed(table));
    _reflow();
  }

  void _hide(String table) {
    setState(() => _c.hide(table));
    _syncFocus();
    _reflow();
  }

  void _showAllTables() {
    setState(_c.hidden.clear);
    _reflow();
  }

  void _dragStart(String table) {
    setState(() => _c.dragging = table);
    _syncFocus();
  }

  /// [screenDelta] is in screen pixels; the canvas may be zoomed.
  void _dragMove(String table, material.Offset screenDelta) {
    final layout = _layout;
    if (_c.dragging != table || layout == null) return;
    final scale = _viewport.scale;
    final delta = screenDelta / (scale == 0 ? 1 : scale);
    // The card follows the pointer at once; the edges are routed once per frame.
    setState(() {
      _layout =
          layout.withPosition(table, layout.positions[table]! + delta);
      _c.followTables(layout, _layout);
    });
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
    if (_c.dragging == null) return;
    setState(() => _c.dragging = null);
    _syncFocus();
    _scheduleSave();
  }

  Future<void> _save(String name, Uint8List bytes) =>
      (widget.onSaveFile ?? defaultErdFileSaver)(name, bytes);

  /// The table whose relations are highlighted: the one being dragged, then
  /// the picked one, then the one under the mouse.

  void _zoomBy(double factor) => _viewport.zoomBy(factor);

  /// Fits the whole diagram into the viewport, centred, never enlarged.
  void _fit() {
    final layout = _layout;
    if (layout == null) return;
    // The cards and every note: a note placed away from the cards counts.
    final floorMoved = _viewport.fit(_c.canvasSize(layout));
    if (floorMoved ?? false) setState(() {});
  }

  /// Picks a table from the search: centres it, closes the search and gives
  /// the keyboard back to the canvas, so Esc then clears the pick.
  void _pickFromSearch(ErdSchema schema, String name) {
    _selectTable(schema, name);
    _searchController.clear();
    setState(() {
      _c.searchOpen = false;
      _c.query = '';
    });
    _canvasFocus.requestFocus();
  }

  /// Picks a table and centres the view on it, keeping the zoom.
  void _selectTable(ErdSchema schema, String name) {
    final layout = _layout;
    final table = schema.tables.firstWhere((t) => t.name == name);
    if (layout != null) {
      final p = layout.positions[name]!;
      _viewport.centreOn(material.Offset(p.dx + layout.widthFor(name) / 2,
          p.dy + ErdLayout.cardHeight(table) / 2));
    }
    setState(() => _c.selected = name);
    _syncFocus();
  }

  /// A click on the empty canvas: clears the pick and takes the keyboard, so
  /// the zoom and search shortcuts work after a click anywhere on it.
  void _clearSelection() {
    _canvasFocus.requestFocus();
    if (!_c.clearPicks()) return;
    setState(() {});
    _edgeTipNotifier.value = null;
    _syncFocus();
  }

  /// A click on the canvas: on an edge it picks the relation, elsewhere it
  /// clears the selection.
  void _tapCanvas(material.Offset p) {
    final hit = _relationAt(p);
    if (hit == null) {
      _clearSelection();
      return;
    }
    _canvasFocus.requestFocus();
    setState(() => _c.pickRelation(hit));
    _edgeTipNotifier.value = (hit, p);
    _syncFocus();
  }

  /// A click on a card picks it.
  void _pick(String name) {
    _canvasFocus.requestFocus();
    setState(() => _c.pick(name));
    _edgeTipNotifier.value = null;
    _syncFocus();
  }

  void _openSearch() {
    setState(() => _c.searchOpen = true);
    material.WidgetsBinding.instance
        .addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  /// Escape: one step per press (see [ErdViewController.escape]); closing
  /// the search keeps the table found.
  void _escape() {
    final step = _c.escape();
    switch (step) {
      case ErdEscape.closedSearch:
        _searchController.clear();
        setState(() {});
        _canvasFocus.requestFocus();
      case ErdEscape.droppedRelation:
        setState(() {});
        _edgeTipNotifier.value = null;
        _syncFocus();
      case ErdEscape.clearedMarks:
        setState(() {});
      case ErdEscape.clearedPick:
        setState(() {});
        _syncFocus();
      case ErdEscape.nothing:
        break;
    }
  }

  List<ErdTable> _matches(ErdSchema schema) =>
      ErdLayoutEngine.matches(schema, _c.query);

  /// Keyboard shortcuts for both Ctrl (Linux, Windows) and Cmd (macOS).
  Map<material.ShortcutActivator, material.VoidCallback> _bindings() {
    final out = <material.ShortcutActivator, material.VoidCallback>{};
    void both(LogicalKeyboardKey key, material.VoidCallback action,
        {bool shift = false}) {
      out[material.SingleActivator(key, control: true, shift: shift)] = action;
      out[material.SingleActivator(key, meta: true, shift: shift)] = action;
    }

    both(LogicalKeyboardKey.equal, () => _zoomBy(ErdViewport.zoomStep));
    // "+" is Shift+= on most layouts.
    both(LogicalKeyboardKey.equal, () => _zoomBy(ErdViewport.zoomStep), shift: true);
    both(LogicalKeyboardKey.add, () => _zoomBy(ErdViewport.zoomStep));
    both(LogicalKeyboardKey.numpadAdd, () => _zoomBy(ErdViewport.zoomStep));
    both(LogicalKeyboardKey.minus, () => _zoomBy(1 / ErdViewport.zoomStep));
    both(LogicalKeyboardKey.numpadSubtract, () => _zoomBy(1 / ErdViewport.zoomStep));
    both(LogicalKeyboardKey.digit0, _fit);
    both(LogicalKeyboardKey.keyF, _openSearch);
    out[const material.SingleActivator(LogicalKeyboardKey.escape)] = _escape;
    return out;
  }

  String? _currentFocus() => _c.currentFocus(_hovered.value);

  ErdCardFocus _cardFocusFor(String table, String? focus) =>
      _c.cardFocusFor(table, focus);

  /// The notifier of card [table], made on first use with its current focus.
  material.ValueNotifier<ErdCardFocus> _cardState(String table) =>
      _cardStates.putIfAbsent(
        table,
        () => material.ValueNotifier(_cardFocusFor(table, _currentFocus())),
      );

  /// Pushes the focus to the edges and to each card. A notifier only fires
  /// when its own highlight or fade changed, so the rest are not rebuilt.
  /// Call after any change to [_c.selected], [_c.dragging] or [_hovered].
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
  /// Header colour of [table] on screen: the picked slot, the schema's slot,
  /// or the accent for a table of the current schema.
  material.Color _headerColor(String table) {
    final slot = erdHeaderSlot(table, _c.headerColors);
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
    setState(() => _c.setHeaderColor(table, slot));
    _scheduleSave();
  }

  /// Header bands for the SVG: the screen's tint over the export's card colour.
  Map<String, String> _headerFills(ErdSchema schema, String cardHex) =>
      ErdExportData.headerFills(
        schema,
        cardHex,
        headerColors: _c.headerColors,
        headerColor: _headerColor,
      );

  /// The toolbar's view switcher: All tables, the saved views, and the
  /// commands to save, rename and delete one.
  material.Widget _viewsMenu() => ErdViewsMenu(
        views: _c.views,
        active: _c.viewById(_c.activeView),
        onShowAll: () => _switchView(null),
        onSwitch: _switchView,
        onNew: () => unawaited(_newView()),
        onRename: () => unawaited(_renameView()),
        onDelete: _deleteView,
      );

  /// Notes for the SVG, tinted as on screen over the export background.
  List<ErdSvgNote> _svgNotes(ErdSvgColors colors) => ErdExportData.notes(
        _c.notes,
        colors,
        slotColor: _slotColor,
        noteTint: _noteTint,
      );

  /// Group frames for the SVG: the screen's tint over the export background.
  List<ErdSvgGroup> _svgGroups(ErdLayout layout, String backgroundHex) =>
      ErdExportData.groups(
        _c.allGroups(_schema),
        layout,
        backgroundHex,
        slotColor: _slotColor,
      );

  /// A group's frame: a tinted box that takes no pointer, and its title,
  /// which drags the whole group and has the group's menu.
  List<material.Widget> _groupFrame(ErdGroup g, ErdLayout layout) =>
      ErdGroupFrame.build(
        group: g,
        layout: layout,
        slotColor: _slotColor,
        dragging: _c.draggingGroup == g.id,
        onFocusCanvas: _canvasFocus.requestFocus,
        onDragStart: () => _groupDragStart(g.id),
        onDragMove: (delta) => _groupDragMove(g, delta),
        onDragEnd: _groupDragEnd,
        onEdit: () => unawaited(_editGroup(g)),
        onColor: (slot) => _updateGroup(g.id, (o) => o.copyWith(color: slot)),
        onUngroup: () => _ungroup(g.id),
      );

  /// Colours of the current theme for the SVG export, as the screen draws the
  /// cards and edges.
  ErdSvgColors _svgColors() => ErdExportData.themeColors(context);

  // ---- ErdExportSource (the export flows live in erd_exporter.dart) -------

  @override
  material.BuildContext get exportContext => context;

  @override
  bool get exportMounted => mounted;

  /// `<database>-erd`, or `erd` when the database name is unknown.
  @override
  String get fileStem =>
      widget.databaseName.isEmpty ? 'erd' : '${widget.databaseName}-erd';

  @override
  Future<void> saveFile(String name, Uint8List bytes) => _save(name, bytes);

  @override
  List<ErdRoute> get routes => _routes;

  @override
  List<ErdGroup> get groups => _c.groups;

  @override
  List<ErdNote> get notes => _c.notes;

  @override
  Map<String, String> get headerColorSlots => _c.headerColors;

  @override
  material.Color slotColor(String slot) => _slotColor(slot);

  @override
  material.Size canvasSize(ErdLayout layout) => _c.canvasSize(layout);

  @override
  ErdSvgColors currentThemeColors() => _svgColors();

  @override
  Map<String, String> headerFills(ErdSchema schema, String cardHex) =>
      _headerFills(schema, cardHex);

  @override
  List<ErdSvgGroup> svgGroups(ErdLayout layout, String backgroundHex) =>
      _svgGroups(layout, backgroundHex);

  @override
  List<ErdSvgNote> svgNotes(ErdSvgColors colors) => _svgNotes(colors);

  @override
  RenderRepaintBoundary? get canvasBoundary =>
      _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

  @override
  Future<void> withCleanCanvas(Future<void> Function() capture) async {
    // The pick, a picked relation and the marks for a group are screen
    // state: none of them belongs in the image, and all come back after it.
    final picked = _c.selected;
    final pickedRelation = _c.pickedRelation;
    final marked = Set.of(_c.marked);
    final hadScreenState = picked != null ||
        pickedRelation != null ||
        marked.isNotEmpty;
    final needsFrame = hadScreenState ||
        _hovered.value != null ||
        _edgeTipNotifier.value != null;
    _hovered.value = null;
    _edgeTipNotifier.value = null;
    if (hadScreenState) {
      setState(() {
        _c.selected = null;
        _c.pickedRelation = null;
        _c.marked.clear();
      });
      _syncFocus();
    }
    try {
      if (needsFrame) await material.WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await capture();
    } finally {
      if (mounted && hadScreenState) {
        setState(() {
          // What the user did during the capture wins.
          if (_c.selected == null && _c.pickedRelation == null) {
            _c.selected = picked;
            _c.pickedRelation = pickedRelation;
          }
          if (_c.marked.isEmpty) _c.marked.addAll(marked);
        });
        _syncFocus();
      }
    }
  }

  void _export(ErdExportAction action, ErdSchema schema, ErdLayout layout) =>
      _exporter.export(action, schema, layout);

  /// Pointer over the canvas ([p] in canvas space): names the relation within
  /// 6 screen px of it, if any, whatever the zoom.
  void _hoverCanvas(material.Offset p) {
    // A picked relation keeps its label until Esc or another click.
    if (_c.pickedRelation != null) return;
    final hit = _relationAt(p);
    // Only the tip layer listens: no rebuild of the view for a hover move.
    _edgeTipNotifier.value = hit == null ? null : (hit, p);
  }

  /// The relation within 6 screen px of [p] (canvas space), whatever the zoom.
  ErdRelation? _relationAt(material.Offset p) {
    ErdRelation? hit;
    final scale = _viewport.scale;
    var best = 6.0 / (scale <= 0 ? 1 : scale);
    for (final r in _routes) {
      final d = ErdGeometry.distanceToRoute(r.points, p);
      if (d <= best) {
        best = d;
        hit = r.relation;
      }
    }
    return hit;
  }

  void _leaveCanvas() {
    if (_c.pickedRelation != null) return;
    _edgeTipNotifier.value = null;
  }

  /// Find-a-table field and the tables it matches. Enter picks the first.
  material.Widget _searchPanel(ErdSchema schema) {
    if (!_c.searchOpen) return const material.SizedBox.shrink();
    return ErdSearchPanel(
      controller: _searchController,
      focusNode: _searchFocus,
      query: _c.query,
      matches: _matches(schema),
      onChanged: (v) => setState(() => _c.query = v.trim()),
      onPick: (name) => _pickFromSearch(schema, name),
    );
  }

  late final _cardCache = ErdCardCache(
    isMounted: () => mounted,
    rebuild: () => setState(() {}),
  );

  List<material.Widget> _cards(ErdSchema schema, ErdLayout layout) {
    final menuKey = Object.hash(
      Object.hashAll(_c.marked),
      Object.hashAll([
        for (final g in _c.groups)
          Object.hash(g.id, g.name, Object.hashAll(g.tables)),
      ]),
    );
    // The palette is built anew on each read; its slot colours are what the
    // cards and the menu use.
    final p = context.semanticPalette;
    final palette = (p.type1, p.type2, p.type3, p.type4, p.type5);
    return _cardCache.cards(
      tables: schema.tables,
      inputsFor: (t) => ErdCardInputs(
        columns: t.columns,
        comment: t.comment,
        position: layout.positions[t.name]!,
        width: layout.widthFor(t.name),
        headerColor: _headerColor(t.name),
        collapsed: _c.collapsed.contains(t.name),
        marked: _c.marked.contains(t.name),
        dragging: _c.dragging == t.name,
        junctionOf: _c.junctions[t.name],
        menuKey: menuKey,
        palette: palette,
        onOpenTable: widget.onOpenTable,
        onOpenInSql: widget.onOpenInSql,
        onShowRelations: widget.onShowRelations,
      ),
      build: (t) => _card(t, layout),
    );
  }

  material.Widget _card(ErdTable t, ErdLayout layout) {
    return material.Positioned(
    left: layout.positions[t.name]!.dx,
    top: layout.positions[t.name]!.dy,
    // Each card listens to its own focus, so a hover
    // rebuilds only the cards it changes.
    child: material.ValueListenableBuilder<ErdCardFocus>(
      valueListenable: _cardState(t.name),
      builder: (context, focus, _) => material.Opacity(
        // Unrelated cards fade while a table is picked.
        opacity: focus.faded ? 0.35 : 1,
        child: QueryaContextMenu(
        items: ErdTableMenu.items(
          table: t.name,
          onOpenData: widget.onOpenTable,
          onOpenInSql: widget.onOpenInSql,
          onShowRelations: widget.onShowRelations,
          collapsed: _c.collapsed.contains(t.name),
          onToggleCollapsed: () =>
              _toggleCollapsed(t.name),
          onHide: () => _hide(t.name),
          groupItems: erdGroupMenu(
            table: t.name,
            marked: _c.marked,
            groups: _c.groups,
            current: _c.groupOf(t.name),
            mutedColor: context.workbench.mutedForeground,
            onNewGroup: (tables) => unawaited(_newGroup(tables)),
            onAddToGroup: _addToGroup,
            onRemoveFromGroup: _removeFromGroup,
          ),
          slotColor: _slotColor,
          onHeaderColor: (slot) =>
              _setHeaderColor(t.name, slot),
        ),
        child: ErdTableCard(
        table: t,
        width: layout.widthFor(t.name),
        headerColor: _headerColor(t.name),
        highlighted: focus.highlighted,
        focusColumn: focus.column,
        junctionOf: _c.junctions[t.name],
        dragging: _c.dragging == t.name,
        onOpen: widget.onOpenTable == null
            ? null
            : () => widget.onOpenTable!(t.name),
        marked: _c.marked.contains(t.name),
        onSelect: () => _tapCard(t.name),
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
  );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final full = _schema;
    final schema = full == null ? null : _visibleOf(full);
    final layout = _layout;
    material.Widget body;
    if (_loading) {
      body = const material.Center(
          child: QueryaSpinner(label: 'Loading schema…'));
    } else if (_error != null) {
      body = ErdStatusBody.error(context, message: _error, onRetry: _load);
    } else if (full != null && full.tables.isNotEmpty && schema!.isEmpty) {
      // Every table was hidden from the diagram: they exist, so say so and
      // offer them back instead of "No tables found".
      body = ErdStatusBody.allHidden(context,
          hiddenCount: _c.hidden.length, onShowAll: _showAllTables);
    } else if (schema == null || layout == null || schema.isEmpty) {
      body = ErdStatusBody.noTables(context,
          databaseName: widget.databaseName);
    } else if (widget.neighbourhoodDepth != null &&
        widget.focusTable != null &&
        schema.relations.isEmpty) {
      body = ErdStatusBody.noRelations(context,
          focusTable: widget.focusTable,
          onOpenFullDiagram: widget.onOpenFullDiagram);
    } else {
      body = ErdCanvas(
        viewport: _viewport,
        boundaryKey: _boundaryKey,
        canvasFocus: _canvasFocus,
        bindings: _bindings(),
        canvasSize: _c.canvasSize(layout),
        panEnabled: _c.dragging == null && _c.draggingGroup == null,
        routes: _routes,
        focus: _focus,
        pickedRelation: _c.pickedRelation,
        edgeTip: _edgeTipNotifier,
        edgeTipLabel: (relation) => ErdEdgeTipLabel(relation: relation),
        onTapUp: _tapCanvas,
        onHover: _hoverCanvas,
        onLeave: _leaveCanvas,
        groupFrames: [
          for (final g in _c.allGroups(_schema)) ..._groupFrame(g, layout),
        ],
        cards: _cards(schema, layout),
        notes: [for (final n in _c.notes) _noteWidget(n)],
        searchPanel: _searchPanel(schema),
        onZoomIn: () => _zoomBy(ErdViewport.zoomStep),
        onZoomOut: () => _zoomBy(1 / ErdViewport.zoomStep),
        onFit: _fit,
      );
    }
    final ready = schema != null && layout != null && !schema.isEmpty;
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        ErdToolbar(
          ready: ready,
          loading: _loading,
          detail: _c.detail,
          markedCount: _c.marked.length,
          hiddenCount: _c.hidden.length,
          viewsMenu: _persists &&
                  !_loading &&
                  _error == null &&
                  (_schema?.tables.isNotEmpty ?? false)
              ? _viewsMenu()
              : null,
          onRefresh: _load,
          onDetail: (d) {
            if (d == _c.detail) return;
            setState(() => _c.detail = d);
            _reflow();
          },
          onAddNote: () => unawaited(_addNote()),
          onGroupMarked: () => unawaited(_newGroup({..._c.marked})),
          onShowHidden: _showAllTables,
          onAutoLayout: _autoLayout,
          onExport: (action) {
            if (schema != null && layout != null) _export(action, schema, layout);
          },
        ),
        material.Expanded(child: material.ClipRect(child: body)),
      ],
    );
  }
}
