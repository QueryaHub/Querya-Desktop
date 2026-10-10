import 'dart:async';
import 'dart:convert';
import 'dart:math' show max, min;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HardwareKeyboard, LogicalKeyboardKey;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/erd/erd_canvas_controls.dart';
import 'package:querya_desktop/features/erd/erd_card_measure.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/features/erd/erd_export_data.dart';
import 'package:querya_desktop/core/erd/erd_geometry.dart';
import 'package:querya_desktop/features/erd/erd_group_dialog.dart';
import 'package:querya_desktop/features/erd/erd_note_dialog.dart';
import 'package:querya_desktop/features/erd/erd_view_name_dialog.dart';
import 'package:querya_desktop/core/erd/erd_group_ops.dart';
import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_layout_engine.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_note_ops.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/core/erd/erd_router.dart';
import 'package:querya_desktop/features/erd/widgets/erd_edge_tip_label.dart';
import 'package:querya_desktop/features/erd/widgets/erd_export_menu.dart';
import 'package:querya_desktop/features/erd/widgets/erd_group_frame.dart';
import 'package:querya_desktop/features/erd/widgets/erd_note_card.dart';
import 'package:querya_desktop/features/erd/widgets/erd_relation_painter.dart';
import 'package:querya_desktop/features/erd/widgets/erd_search_panel.dart';
import 'package:querya_desktop/features/erd/widgets/erd_status_body.dart';
import 'package:querya_desktop/features/erd/widgets/erd_table_menu.dart';
import 'package:querya_desktop/features/erd/widgets/erd_views_menu.dart';
import 'package:querya_desktop/features/erd/widgets/erd_table_card.dart';
import 'package:querya_desktop/core/export/image_pdf.dart';
import 'package:querya_desktop/core/export/svg_png.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';
import 'package:querya_desktop/features/workspace/sql_editor_chrome.dart';
import 'package:querya_desktop/shared/widgets/querya_action_button.dart';
import 'package:querya_desktop/shared/widgets/querya_spinner.dart';
import 'package:querya_desktop/shared/widgets/querya_tab_strip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

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
  final _cardStates = <String, material.ValueNotifier<ErdCardFocus>>{};
  Map<String, Set<String>> _neighbours = const {};

  /// Density: only PK and FK columns, cards collapsed to their header, and
  /// tables hidden from the diagram. Layout and routing follow the visible
  /// schema from [_visibleOf].
  ErdDetail _detail = ErdDetail.all;
  final Set<String> _collapsed = {};
  final Set<String> _hidden = {};

  /// A relation picked by a click on its edge (#1281): its two tables and
  /// columns are highlighted and its label stays until Esc.
  ErdRelation? _pickedRelation;

  /// Many-to-many link tables and what they link: `users and roles` (#1281).
  Map<String, String> _junctions = const {};

  /// Header colour picked per table (palette slot names, #1276).
  final Map<String, String> _headerColors = {};

  /// The user's table groups, saved with the layout (#1282).
  final List<ErdGroup> _groups = [];

  /// Tables marked with Shift / Ctrl / Cmd + click, to be grouped.
  final Set<String> _marked = {};

  /// The group whose frame is being dragged by its title.
  String? _draggingGroup;

  /// Saved views of the diagram (#1284), the one the user is in, and the
  /// *All tables* state while a view is active.
  final List<ErdSavedView> _views = [];
  String? _activeView;
  ErdSavedLayout _base = const ErdSavedLayout();

  /// Sticky notes on the canvas, saved with the layout (#1283).
  final List<ErdNote> _notes = [];
  String? _draggingNote;

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
      final stored = await _readSaved(schema);
      if (!mounted) return;
      // The state to show: the diagram's own, or the view it was left in.
      var saved = stored;
      if (stored != null) {
        _base = stored;
        _views
          ..clear()
          ..addAll(stored.views);
        _activeView = stored.activeView;
        final view = _viewById(_activeView);
        if (view != null) {
          saved = view.asLayout(
              {for (final t in schema.tables) t.name}, stored.headerColors);
        }
      }
      setState(() {
        _schema = schema;
        _neighbours = ErdLayoutEngine.neighbourMap(schema);
        _junctions = ErdLayoutEngine.junctionMap(schema);
        _pickedRelation = null;
        if (saved != null) _applyState(saved, colours: true);
        _marked.clear();
        _setLayout(ErdLayoutEngine.withSaved(_compute(_visibleOf(schema)), saved));
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

  /// The state of the diagram a [ErdSavedLayout] holds: what is collapsed
  /// and hidden, the detail, groups and notes. Header colours belong to the
  /// diagram, so a view switch leaves them ([colours] false).
  void _applyState(ErdSavedLayout s, {required bool colours}) {
    _collapsed
      ..clear()
      ..addAll(s.collapsed);
    _hidden
      ..clear()
      ..addAll(s.hidden);
    _detail = s.detail;
    if (colours) {
      _headerColors
        ..clear()
        ..addAll(s.headerColors);
    }
    _groups
      ..clear()
      ..addAll(s.groups);
    _notes
      ..clear()
      ..addAll(s.notes);
  }

  /// Layout with cards measured in this view's fonts and text scale.
  ErdLayout _compute(ErdSchema schema) {
    final measure = ErdCardMeasure(
      base: material.DefaultTextStyle.of(context).style,
      textScaler: material.MediaQuery.textScalerOf(context),
    );
    return ErdLayout.compute(schema,
        measure: measure.width,
        groups: [for (final g in _allGroups()) g.tables]);
  }

  /// The user's groups, then one per schema for the tables in none when the
  /// diagram spans several schemas.
  List<ErdGroup> _allGroups() {
    final schema = _schema;
    if (schema == null) return List.of(_groups);
    return [
      ..._groups,
      ...erdSchemaGroups([for (final t in schema.tables) t.name], _groups),
    ];
  }

  ErdGroup? _groupOf(String table) => ErdGroupOps.groupOf(_groups, table);

  void _replaceGroups(List<ErdGroup> groups) {
    final next = List.of(groups);
    _groups
      ..clear()
      ..addAll(next);
  }

  /// Asks for a name and groups [tables], taking them out of other groups.
  Future<void> _newGroup(Set<String> tables) async {
    if (tables.isEmpty) return;
    final n = ErdGroupOps.nextNameNumber(_groups);
    final text = await showErdGroupDialog(context,
        title: 'New group', action: 'Create', name: 'Group $n');
    if (text == null || !mounted) return;
    setState(() {
      _replaceGroups(ErdGroupOps.withNewGroup(
        _groups,
        tables: tables,
        tableNames: [for (final t in _schema?.tables ?? const <ErdTable>[]) t.name],
        name: text.name,
        note: text.note,
      ));
      _marked.clear();
    });
    _gatherIfCovering(_groups.last.id);
    _scheduleSave();
  }

  /// A group frame that would cover other cards: the group's tables are
  /// packed into one block, the other cards stay (#1282).
  void _gatherIfCovering(String id) {
    final layout = _layout;
    final i = _groups.indexWhere((g) => g.id == id);
    if (layout == null || i < 0) return;
    final tables = _groups[i].tables;
    if (!layout.frameCoversOthers(tables)) return;
    setState(() {
      _setLayout(layout.gather(tables));
      _followTables(layout);
    });
    showAppToast(
      context: context,
      message: 'Moved the tables of "${_groups[i].name}" together so its '
          'frame covers no other table.',
    );
  }

  void _addToGroup(String id, Set<String> tables) {
    setState(() {
      _replaceGroups(ErdGroupOps.addTables(_groups, id, tables));
      if (_groups.any((g) => g.id == id)) _marked.clear();
    });
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
    final i = _groups.indexWhere((g) => g.id == id);
    if (i < 0) return;
    setState(() => _groups[i] = change(_groups[i]));
    _scheduleSave();
  }

  void _ungroup(String id) {
    setState(() => _groups.removeWhere((g) => g.id == id));
    _scheduleSave();
  }

  void _removeFromGroup(String table) {
    setState(() => _replaceGroups(ErdGroupOps.ungroupTables(_groups, {table})));
    _scheduleSave();
  }

  /// A click on a card: with Shift, Ctrl or Cmd it marks or unmarks the table
  /// for a group, otherwise it picks it.
  void _tapCard(String table) {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed || keys.isControlPressed || keys.isMetaPressed) {
      _canvasFocus.requestFocus();
      setState(() {
        if (!_marked.remove(table)) _marked.add(table);
      });
      return;
    }
    if (_marked.isNotEmpty) setState(_marked.clear);
    _pick(table);
  }

  /// Applies [target] (a view's state, or the diagram's own) and its
  /// viewport, after the current state was kept where it belongs.
  void _showState(String? viewId, ErdSavedLayout target) {
    final schema = _schema;
    if (schema == null) return;
    setState(() {
      _activeView = viewId;
      _selected = null;
      _pickedRelation = null;
      _marked.clear();
      _applyState(target, colours: false);
      _setLayout(ErdLayoutEngine.withSaved(_compute(_visibleOf(schema)), target));
    });
    _syncFocus();
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scale = target.scale, translation = target.translation;
      if (scale != null && translation != null) {
        _restoring = true;
        _transform.value = Matrix4.identity()
          ..translate(translation.dx, translation.dy)
          ..scale(scale);
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
    if (schema == null || id == _activeView) return;
    _captureCurrent();
    if (id == null) {
      _showState(null, _base);
      return;
    }
    final view = _viewById(id);
    if (view == null) return;
    _showState(
        id,
        view.asLayout({for (final t in schema.tables) t.name}, _headerColors));
  }

  /// Saves what the diagram shows as a new view and moves into it.
  Future<void> _newView() async {
    final schema = _schema;
    if (schema == null) return;
    final name = await showErdViewNameDialog(context,
        title: 'New view',
        action: 'Save',
        name: 'View ${_views.length + 1}');
    if (name == null || !mounted) return;
    final fromAll = _viewById(_activeView) == null;
    _captureCurrent();
    // The tables hidden by hand now belong to the view; All tables shows
    // every table, always.
    if (fromAll) _base = _base.showingAll();
    var n = 1;
    while (_views.any((v) => v.id == 'v$n')) {
      n++;
    }
    setState(() {
      _views.add(ErdSavedView(
        id: 'v$n',
        name: name,
        tables: {
          for (final t in schema.tables)
            if (!_hidden.contains(t.name)) t.name,
        },
        layout: _current(),
      ));
      _activeView = 'v$n';
    });
    _scheduleSave();
  }

  Future<void> _renameView() async {
    final view = _viewById(_activeView);
    if (view == null) return;
    final name = await showErdViewNameDialog(context,
        title: 'Rename view', action: 'Rename', name: view.name);
    if (name == null || !mounted) return;
    final i = _views.indexWhere((v) => v.id == view.id);
    if (i < 0) return;
    setState(() => _views[i] = _views[i].copyWith(name: name));
    _scheduleSave();
  }

  /// Deletes the active view and goes back to *All tables*.
  void _deleteView() {
    final id = _activeView;
    if (id == null) return;
    _views.removeWhere((v) => v.id == id);
    _showState(null, _base);
  }

  /// Moves the notes attached to a table by what the table moved, from
  /// [before] to the current layout.
  void _followTables(ErdLayout before) {
    final after = _layout;
    if (after == null || _notes.every((n) => n.attachedTo == null)) return;
    for (var i = 0; i < _notes.length; i++) {
      final t = _notes[i].attachedTo;
      if (t == null) continue;
      final a = before.positions[t], b = after.positions[t];
      if (a == null || b == null || a == b) continue;
      final d = b - a;
      _notes[i] = _notes[i]
          .copyWith(x: _notes[i].x + d.dx, y: _notes[i].y + d.dy);
    }
  }

  /// Canvas point at the middle of what the viewport shows.
  material.Offset _viewCentre() {
    final vs = _viewportSize();
    if (vs == null) return const material.Offset(60, 60);
    final inverse = Matrix4.inverted(_transform.value);
    final p = material.MatrixUtils.transformPoint(
        inverse, vs.center(material.Offset.zero));
    return p;
  }

  Future<void> _addNote() async {
    final text = await showErdNoteDialog(context,
        title: 'New note', action: 'Add');
    if (text == null || !mounted) return;
    final note =
        ErdNoteOps.create(_notes, text: text, centre: _viewCentre());
    setState(() => _notes.add(note));
    _scheduleSave();
  }

  Future<void> _editNote(ErdNote note) async {
    final text = await showErdNoteDialog(context,
        title: 'Edit note', action: 'Save', text: note.text);
    if (text == null || !mounted) return;
    _updateNote(note.id, (n) => n.copyWith(text: text));
  }

  void _updateNote(String id, ErdNote Function(ErdNote) change) {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    setState(() => _notes[i] = change(_notes[i]));
    _scheduleSave();
  }

  void _deleteNote(String id) {
    setState(() => _notes.removeWhere((n) => n.id == id));
    _scheduleSave();
  }

  void _noteDragMove(String id, material.Offset screenDelta) {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    final moved = ErdNoteOps.moved(_notes[i], screenDelta, _scale);
    setState(() => _notes[i] = moved);
  }

  void _noteResize(String id, material.Offset screenDelta) {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    final resized = ErdNoteOps.resized(_notes[i], screenDelta, _scale);
    setState(() => _notes[i] = resized);
  }

  /// The table nearest to a note's middle, to attach it to.
  String? _nearestTable(ErdNote n) {
    final layout = _layout;
    final schema = _schema;
    if (layout == null || schema == null) return null;
    return ErdNoteOps.nearestTable(n, layout, _visibleOf(schema));
  }

  /// Canvas size: the cards and every note.
  material.Size _canvasSize(ErdLayout layout) {
    var w = layout.size.width, h = layout.size.height;
    for (final n in _notes) {
      w = max(w, n.x + n.width + ErdLayout.margin);
      h = max(h, n.y + n.height + ErdLayout.margin);
    }
    return material.Size(w, h);
  }

  /// Tint of a note without a colour over the canvas, on screen and in the
  /// exports.
  static const double _noteTint = 0.07;

  material.Widget _noteWidget(ErdNote n) => ErdNoteCard(
        note: n,
        tint: _noteTint,
        slotColor: _slotColor,
        dragging: _draggingNote == n.id,
        onFocusCanvas: _canvasFocus.requestFocus,
        onDragStart: () => setState(() => _draggingNote = n.id),
        onDragMove: (d) => _noteDragMove(n.id, d),
        onDragEnd: () {
          setState(() => _draggingNote = null);
          _scheduleSave();
        },
        onDragCancel: () => setState(() => _draggingNote = null),
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

  void _groupDragStart(String id) => setState(() => _draggingGroup = id);

  /// Moves every visible table of [group] by [screenDelta], keeping its frame
  /// inside the canvas.
  void _groupDragMove(ErdGroup group, material.Offset screenDelta) {
    final layout = _layout;
    if (_draggingGroup != group.id || layout == null) return;
    final frame = layout.frameOf(group.tables);
    if (frame == null) return;
    final scale = _scale;
    var delta = screenDelta / (scale == 0 ? 1 : scale);
    delta = material.Offset(
        max(delta.dx, -frame.left), max(delta.dy, -frame.top));
    setState(() {
      _layout = layout.withPositions({
        for (final t in group.tables)
          if (layout.positions[t] case final p?) t: p + delta,
      });
      _followTables(layout);
    });
    _scheduleRoutes();
  }

  void _groupDragEnd() {
    if (_draggingGroup == null) return;
    setState(() => _draggingGroup = null);
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
  ErdSavedLayout _current() {
    final m = _transform.value;
    final t = m.getTranslation();
    return ErdSavedLayout(
      positions: Map.of(_layout?.positions ?? const {}),
      collapsed: Set.of(_collapsed),
      hidden: Set.of(_hidden),
      detail: _detail,
      headerColors: Map.of(_headerColors),
      groups: List.of(_groups),
      notes: List.of(_notes),
      scale: m.getMaxScaleOnAxis(),
      translation: material.Offset(t.x, t.y),
    );
  }

  /// Writes the current state to where it belongs: the active view, or the
  /// diagram's own (*All tables*) state.
  void _captureCurrent() {
    final schema = _schema;
    if (schema == null || _layout == null) return;
    final cur = _current();
    final i = _views.indexWhere((v) => v.id == _activeView);
    if (i < 0) {
      _base = cur;
      return;
    }
    _views[i] = ErdSavedView(
      id: _views[i].id,
      name: _views[i].name,
      tables: {
        for (final t in schema.tables)
          if (!_hidden.contains(t.name)) t.name,
      },
      layout: cur,
    );
  }

  ErdSavedView? _viewById(String? id) {
    for (final v in _views) {
      if (v.id == id) return v;
    }
    return null;
  }

  Future<void> _saveNow() async {
    final layout = _layout;
    if (!_persists || layout == null) return;
    _captureCurrent();
    try {
      await widget.layoutStore!.write(
        widget.layoutKey!,
        // The diagram's own state, with the header colours as they are now.
        _base.withViews(List.of(_views), _activeView,
            headerColors: Map.of(_headerColors)),
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

  /// The schema as drawn, for the current density and visibility.
  ErdSchema _visibleOf(ErdSchema schema) => ErdLayoutEngine.visibleOf(
        schema,
        hidden: _hidden,
        collapsed: _collapsed,
        detail: _detail,
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
      if (current != null) _followTables(current);
    });
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
      _marked.remove(table);
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
    setState(() {
      _layout =
          layout.withPosition(table, layout.positions[table]! + delta);
      _followTables(layout);
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
    // The cards and every note: a note placed away from the cards counts.
    final size = _canvasSize(layout);
    final s = ErdLayout.fitScale(size, vs);
    final floor = min(_minScale, s);
    if (floor != _zoomFloor) setState(() => _zoomFloor = floor);
    final tx = (vs.width - size.width * s) / 2;
    final ty = (vs.height - size.height * s) / 2;
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
    if (_selected == null && _pickedRelation == null && _marked.isEmpty) {
      return;
    }
    setState(() {
      _selected = null;
      _pickedRelation = null;
      _marked.clear();
    });
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
    setState(() {
      _pickedRelation = hit;
      _selected = null;
    });
    _edgeTipNotifier.value = (hit, p);
    _syncFocus();
  }

  /// A click on a card picks it.
  void _pick(String name) {
    _canvasFocus.requestFocus();
    setState(() {
      _selected = name;
      _pickedRelation = null;
    });
    _edgeTipNotifier.value = null;
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
    if (_pickedRelation != null) {
      setState(() => _pickedRelation = null);
      _edgeTipNotifier.value = null;
      _syncFocus();
      return;
    }
    if (_marked.isNotEmpty) {
      setState(_marked.clear);
      return;
    }
    if (_selected != null) {
      setState(() => _selected = null);
      _syncFocus();
    }
  }

  List<ErdTable> _matches(ErdSchema schema) =>
      ErdLayoutEngine.matches(schema, _query);

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

  /// The table the diagram focuses: the dragged one, then the picked one, then
  /// the one under the mouse.
  String? _currentFocus() => _dragging ?? _selected ?? _hovered.value;

  ErdCardFocus _cardFocusFor(String table, String? focus) {
    final p = _pickedRelation;
    if (p != null) {
      final on = table == p.fromTable || table == p.toTable;
      final column = table == p.fromTable
          ? p.fromColumn
          : (table == p.toTable ? p.toColumn : null);
      return (highlighted: on, faded: !on, column: column);
    }
    final highlighted = ErdLayoutEngine.isFocusedIn(_neighbours, focus, table);
    return (
      highlighted: highlighted,
      faded: _selected != null && !highlighted,
      column: null,
    );
  }

  /// The notifier of card [table], made on first use with its current focus.
  material.ValueNotifier<ErdCardFocus> _cardState(String table) =>
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
      final scale = ErdExport.pngPixelRatio(_canvasSize(layout));
      final svg = ErdExport.toSvg(schema, layout,
          routes: _routes,
          headerFills: _headerFills(schema, const ErdSvgColors().card),
          groups: _svgGroups(layout, const ErdSvgColors().background),
          notes: _svgNotes(const ErdSvgColors()));
      await _save('$_fileStem.png', await svgToPng(svg, scale: scale));
      return;
    }
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    // The pick, a picked relation and the marks for a group are screen
    // state: none of them belongs in the image, and all come back after it.
    final picked = _selected;
    final pickedRelation = _pickedRelation;
    final marked = Set.of(_marked);
    final needsFrame = picked != null ||
        pickedRelation != null ||
        marked.isNotEmpty ||
        _hovered.value != null ||
        _edgeTipNotifier.value != null;
    _hovered.value = null;
    _edgeTipNotifier.value = null;
    if (picked != null || pickedRelation != null || marked.isNotEmpty) {
      setState(() {
        _selected = null;
        _pickedRelation = null;
        _marked.clear();
      });
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
      if (mounted &&
          (picked != null || pickedRelation != null || marked.isNotEmpty)) {
        setState(() {
          // What the user did during the capture wins.
          if (_selected == null && _pickedRelation == null) {
            _selected = picked;
            _pickedRelation = pickedRelation;
          }
          if (_marked.isEmpty) _marked.addAll(marked);
        });
        _syncFocus();
      }
    }
  }

  /// The diagram as SVG text, in the export palette: light for documents,
  /// unless the setting asks for the current theme.
  Future<String?> _svgText(ErdSchema schema, ErdLayout layout) async {
    final currentTheme = await AppSettings.instance.getExportCurrentTheme();
    if (!mounted) return null;
    final colors = currentTheme ? _svgColors() : const ErdSvgColors();
    return ErdExport.toSvg(schema, layout,
        routes: _routes,
        colors: colors,
        headerFills: _headerFills(schema, colors.card),
        groups: _svgGroups(layout, colors.background),
        notes: _svgNotes(colors));
  }

  /// The SVG export.
  Future<void> _exportSvg(ErdSchema schema, ErdLayout layout) async {
    final svg = await _svgText(schema, layout);
    if (svg == null) return;
    await _save('$_fileStem.svg', Uint8List.fromList(utf8.encode(svg)));
  }

  /// The PDF export: the SVG fitted on one page of [paper].
  Future<void> _exportPdf(
      ErdSchema schema, ErdLayout layout, PdfPaper paper) async {
    final svg = await _svgText(schema, layout);
    if (svg == null) return;
    try {
      await _save('$_fileStem.pdf', await svgToPdf(svg, paper: paper));
    } catch (e) {
      if (mounted) {
        showAppToast(
          context: context,
          variant: AppToastVariant.error,
          message: 'Could not render the PDF ($e). Export SVG instead.',
        );
      }
    }
  }

  /// The DBML of what the diagram shows: its groups and notes, and the
  /// header colours it draws.
  String _dbml(ErdSchema schema) {
    final shown = {for (final t in schema.tables) t.name};
    return ErdExport.toDbml(
      schema,
      groups: [
        for (final g in _groups)
          if (g.tables.any(shown.contains)) g,
      ],
      notes: List.of(_notes),
      headerColors: {
        for (final t in schema.tables)
          if (erdHeaderSlot(t.name, _headerColors) case final slot?)
            t.name: ErdSvgColors.hex(_slotColor(slot).toARGB32()),
      },
    );
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
  Map<String, String> _headerFills(ErdSchema schema, String cardHex) =>
      ErdExportData.headerFills(
        schema,
        cardHex,
        headerColors: _headerColors,
        headerColor: _headerColor,
      );

  /// The toolbar's view switcher: All tables, the saved views, and the
  /// commands to save, rename and delete one.
  material.Widget _viewsMenu() => ErdViewsMenu(
        views: _views,
        active: _viewById(_activeView),
        onShowAll: () => _switchView(null),
        onSwitch: _switchView,
        onNew: () => unawaited(_newView()),
        onRename: () => unawaited(_renameView()),
        onDelete: _deleteView,
      );

  /// Group entries of a card's menu: group it (with the marked tables), add
  /// it to a group, take it out of its group.
  List<MenuItem> _groupMenu(String table) {
    final tables = {..._marked, table};
    final current = _groupOf(table);
    return [
      MenuButton(
        key: material.ValueKey('erd_menu_group_$table'),
        onPressed: (_) => unawaited(_newGroup(tables)),
        // The way to put more tables in is not obvious: say it here.
        trailing: tables.length == 1
            ? Text('Shift+click marks more',
                style: material.TextStyle(
                    fontSize: 11, color: context.workbench.mutedForeground))
            : null,
        child: Text(tables.length == 1
            ? 'New group…'
            : 'Group ${tables.length} tables…'),
      ),
      if (_groups.any((g) => g.id != current?.id))
        MenuButton(
          subMenu: [
            for (final g in _groups)
              if (g.id != current?.id)
                MenuButton(
                  onPressed: (_) => _addToGroup(g.id, tables),
                  child: Text(g.name),
                ),
          ],
          child: const Text('Add to group'),
        ),
      if (current != null)
        MenuButton(
          key: material.ValueKey('erd_menu_ungroup_$table'),
          onPressed: (_) => _removeFromGroup(table),
          child: Text('Remove from ${current.name}'),
        ),
    ];
  }

  /// Notes for the SVG, tinted as on screen over the export background.
  List<ErdSvgNote> _svgNotes(ErdSvgColors colors) => ErdExportData.notes(
        _notes,
        colors,
        slotColor: _slotColor,
        noteTint: _noteTint,
      );

  /// Group frames for the SVG: the screen's tint over the export background.
  List<ErdSvgGroup> _svgGroups(ErdLayout layout, String backgroundHex) =>
      ErdExportData.groups(
        _allGroups(),
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
        dragging: _draggingGroup == g.id,
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

  /// `<database>-erd`, or `erd` when the database name is unknown.
  String get _fileStem =>
      widget.databaseName.isEmpty ? 'erd' : '${widget.databaseName}-erd';

  void _export(ErdExportAction action, ErdSchema schema, ErdLayout layout) {
    switch (action) {
      case ErdExportAction.mermaid:
        _save(
            '$_fileStem.mmd',
            Uint8List.fromList(utf8.encode(ErdExport.toMermaid(schema))));
      case ErdExportAction.svg:
        unawaited(_exportSvg(schema, layout));
      case ErdExportAction.png:
        unawaited(_exportPng(schema, layout));
      case ErdExportAction.pdfA4:
        unawaited(_exportPdf(schema, layout, PdfPaper.a4));
      case ErdExportAction.pdfA3:
        unawaited(_exportPdf(schema, layout, PdfPaper.a3));
      case ErdExportAction.dbml:
        _save('$_fileStem.dbml',
            Uint8List.fromList(utf8.encode(_dbml(schema))));
      case ErdExportAction.copyDbml:
        Clipboard.setData(ClipboardData(text: _dbml(schema)));
        showAppToast(
          context: context,
          message: 'DBML copied to the clipboard',
        );
      case ErdExportAction.toggleTheme:
        unawaited(_toggleExportTheme());
      case ErdExportAction.copyMermaid:
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
    // A picked relation keeps its label until Esc or another click.
    if (_pickedRelation != null) return;
    final hit = _relationAt(p);
    // Only the tip layer listens: no rebuild of the view for a hover move.
    _edgeTipNotifier.value = hit == null ? null : (hit, p);
  }

  /// The relation within 6 screen px of [p] (canvas space), whatever the zoom.
  ErdRelation? _relationAt(material.Offset p) {
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
    return hit;
  }

  void _leaveCanvas() {
    if (_pickedRelation != null) return;
    _edgeTipNotifier.value = null;
  }

  /// "orders.customer_id → customers.id" next to the pointer.
  material.Widget _edgeTipLabel(material.BuildContext context, ErdRelation r) =>
      ErdEdgeTipLabel(relation: r);

  /// Find-a-table field and the tables it matches. Enter picks the first.
  material.Widget _searchPanel(ErdSchema schema) {
    if (!_searchOpen) return const material.SizedBox.shrink();
    return ErdSearchPanel(
      controller: _searchController,
      focusNode: _searchFocus,
      query: _query,
      matches: _matches(schema),
      onChanged: (v) => setState(() => _query = v.trim()),
      onPick: (name) => _pickFromSearch(schema, name),
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
      body = ErdStatusBody.error(context, message: _error, onRetry: _load);
    } else if (full != null && full.tables.isNotEmpty && schema!.isEmpty) {
      // Every table was hidden from the diagram: they exist, so say so and
      // offer them back instead of "No tables found".
      body = ErdStatusBody.allHidden(context,
          hiddenCount: _hidden.length, onShowAll: _showAllTables);
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
                // A card or group drag must not pan the canvas.
                panEnabled: _dragging == null && _draggingGroup == null,
                minScale: _zoomFloor,
                maxScale: _maxScale,
                boundaryMargin: const material.EdgeInsets.all(400),
                child: material.RepaintBoundary(
                  key: _boundaryKey,
                  child: material.Container(
                    color: wb.surface,
                    width: _canvasSize(layout).width,
                    height: _canvasSize(layout).height,
                    child: material.GestureDetector(
                      // A tap on an edge picks its relation, elsewhere it clears
                      // the selection (#1281).
                      behavior: material.HitTestBehavior.translucent,
                      onTapUp: (d) => _tapCanvas(d.localPosition),
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
                          // Group frames under the edges and cards (#1282).
                          for (final g in _allGroups())
                            ..._groupFrame(g, layout),
                          material.Positioned.fill(
                            child: material.ValueListenableBuilder<String?>(
                              valueListenable: _focus,
                              builder: (context, focus, _) =>
                                  material.CustomPaint(
                                painter: ErdRelationPainter(
                                  routes: _routes,
                                  color: wb.mutedForeground,
                                  highlight: wb.accent,
                                  focus: focus,
                                  picked: _pickedRelation,
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
                              child: material.ValueListenableBuilder<ErdCardFocus>(
                                valueListenable: _cardState(t.name),
                                builder: (context, focus, _) => material.Opacity(
                                  // Unrelated cards fade while a table is picked.
                                  opacity: focus.faded ? 0.35 : 1,
                                  child: ContextMenu(
                                  items: ErdTableMenu.items(
                                    table: t.name,
                                    onOpenData: widget.onOpenTable,
                                    onOpenInSql: widget.onOpenInSql,
                                    onShowRelations: widget.onShowRelations,
                                    collapsed: _collapsed.contains(t.name),
                                    onToggleCollapsed: () =>
                                        _toggleCollapsed(t.name),
                                    onHide: () => _hide(t.name),
                                    groupItems: _groupMenu(t.name),
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
                                  junctionOf: _junctions[t.name],
                                  dragging: _dragging == t.name,
                                  onOpen: widget.onOpenTable == null
                                      ? null
                                      : () => widget.onOpenTable!(t.name),
                                  marked: _marked.contains(t.name),
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
                            ),
                          // Sticky notes above the cards (#1283).
                          for (final n in _notes) _noteWidget(n),
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
              // Detail level for every card; a card collapsed by hand stays
              // collapsed (#1278).
              material.IgnorePointer(
                ignoring: !ready,
                child: material.Opacity(
                  opacity: ready ? 1 : 0.5,
                  child: material.Tooltip(
                    message: 'Table names only, key columns, or every column',
                    child: QueryaTabStrip(
                      key: const material.ValueKey('erd_detail'),
                      dense: true,
                      labels: const ['Names', 'Keys', 'All'],
                      selectedIndex: ErdDetail.values.indexOf(_detail),
                      onSelected: (i) {
                        if (ErdDetail.values[i] == _detail) return;
                        setState(() => _detail = ErdDetail.values[i]);
                        _reflow();
                      },
                    ),
                  ),
                ),
              ),
              // Also with every table hidden: a view may be that empty, and
              // the way out is another view.
              if (_persists &&
                  !_loading &&
                  _error == null &&
                  (_schema?.tables.isNotEmpty ?? false))
                _viewsMenu(),
              QueryaActionButton(
                key: const material.ValueKey('erd_add_note'),
                label: 'Note',
                icon: material.Icons.sticky_note_2_outlined,
                tooltip: 'Add a sticky note to the diagram',
                onPressed: ready ? () => unawaited(_addNote()) : null,
              ),
              if (_marked.isNotEmpty)
                QueryaActionButton(
                  key: const material.ValueKey('erd_group_marked'),
                  label: 'Group ${_marked.length} '
                      '${_marked.length == 1 ? 'table' : 'tables'}',
                  icon: material.Icons.folder_open_rounded,
                  tooltip: 'Shift / Ctrl + click marks more tables',
                  onPressed: () => unawaited(_newGroup({..._marked})),
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
                  child: ErdExportMenu(
                    onSelected: (action) {
                      if (schema != null && layout != null) {
                        _export(action, schema, layout);
                      }
                    },
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
