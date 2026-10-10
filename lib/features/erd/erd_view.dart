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
    show Clipboard, ClipboardData, HardwareKeyboard, LogicalKeyboardKey;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/features/erd/erd_canvas_controls.dart';
import 'package:querya_desktop/features/erd/erd_card_measure.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/features/erd/erd_geometry.dart';
import 'package:querya_desktop/core/erd/erd_note_text.dart';
import 'package:querya_desktop/features/erd/erd_group_dialog.dart';
import 'package:querya_desktop/features/erd/erd_note_dialog.dart';
import 'package:querya_desktop/features/erd/erd_view_name_dialog.dart';
import 'package:querya_desktop/features/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/features/erd/erd_router.dart';
import 'package:querya_desktop/core/export/image_pdf.dart';
import 'package:querya_desktop/core/export/svg_png.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';
import 'package:querya_desktop/shared/widgets/querya_action_menu.dart';
import 'package:querya_desktop/shared/widgets/querya_empty_state.dart';
import 'package:querya_desktop/shared/widgets/querya_search_field.dart';
import 'package:querya_desktop/features/workspace/sql_editor_chrome.dart';
import 'package:querya_desktop/shared/widgets/querya_action_button.dart';
import 'package:querya_desktop/shared/widgets/querya_spinner.dart';
import 'package:querya_desktop/shared/widgets/querya_tab_strip.dart';
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
enum _ExportAction {
  mermaid,
  svg,
  png,
  pdfA4,
  pdfA3,
  dbml,
  copyMermaid,
  copyDbml,
  toggleTheme,
}

/// A card's focus: related to the focused table, and faded while another
/// table is picked and this one is not related to it.
/// A card's share of the focus: highlighted, faded, and the column of a
/// picked relation on it, if any.
typedef _CardFocus = ({bool highlighted, bool faded, String? column});

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
        _neighbours = _neighbourMap(schema);
        _junctions = _junctionMap(schema);
        _pickedRelation = null;
        if (saved != null) _applyState(saved, colours: true);
        _marked.clear();
        _setLayout(_withSaved(_compute(_visibleOf(schema)), saved));
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

  ErdGroup? _groupOf(String table) {
    for (final g in _groups) {
      if (g.tables.contains(table)) return g;
    }
    return null;
  }

  /// [tables] out of every group but [except]; a group left empty goes.
  void _ungroupTables(Set<String> tables, {String? except}) {
    for (var i = _groups.length - 1; i >= 0; i--) {
      final g = _groups[i];
      if (g.id == except || !g.tables.any(tables.contains)) continue;
      final left = [for (final t in g.tables) if (!tables.contains(t)) t];
      if (left.isEmpty) {
        _groups.removeAt(i);
      } else {
        _groups[i] = g.copyWith(tables: left);
      }
    }
  }

  /// Asks for a name and groups [tables], taking them out of other groups.
  Future<void> _newGroup(Set<String> tables) async {
    if (tables.isEmpty) return;
    var n = _groups.length + 1;
    while (_groups.any((g) => g.name == 'Group $n')) {
      n++;
    }
    final text = await showErdGroupDialog(context,
        title: 'New group', action: 'Create', name: 'Group $n');
    if (text == null || !mounted) return;
    var id = 1;
    while (_groups.any((g) => g.id == 'g$id')) {
      id++;
    }
    setState(() {
      _ungroupTables(tables);
      _groups.add(ErdGroup(
        id: 'g$id',
        name: text.name,
        note: text.note,
        color: erdHeaderSlots[(id - 1) % erdHeaderSlots.length],
        tables: [
          for (final t in _schema?.tables ?? const <ErdTable>[])
            if (tables.contains(t.name)) t.name,
        ],
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
      _ungroupTables(tables, except: id);
      final i = _groups.indexWhere((g) => g.id == id);
      if (i < 0) return;
      final g = _groups[i];
      _groups[i] = g.copyWith(tables: [
        ...g.tables,
        for (final t in tables)
          if (!g.tables.contains(t)) t,
      ]);
      _marked.clear();
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
    setState(() => _ungroupTables({table}));
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
      _setLayout(_withSaved(_compute(_visibleOf(schema)), target));
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
    var n = 1;
    while (_notes.any((o) => o.id == 'n$n')) {
      n++;
    }
    final c = _viewCentre();
    setState(() => _notes.add(ErdNote(
          id: 'n$n',
          text: text,
          x: max(8.0, c.dx - ErdNote.defaultWidth / 2),
          y: max(8.0, c.dy - ErdNote.defaultHeight / 2),
        )));
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
    final scale = _scale;
    final d = screenDelta / (scale == 0 ? 1 : scale);
    final n = _notes[i];
    setState(() => _notes[i] =
        n.copyWith(x: max(0.0, n.x + d.dx), y: max(0.0, n.y + d.dy)));
  }

  void _noteResize(String id, material.Offset screenDelta) {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    final scale = _scale;
    final d = screenDelta / (scale == 0 ? 1 : scale);
    final n = _notes[i];
    setState(() => _notes[i] = n.copyWith(
          width: max(ErdNote.minWidth, n.width + d.dx),
          height: max(ErdNote.minHeight, n.height + d.dy),
        ));
  }

  /// The table nearest to a note's middle, to attach it to.
  String? _nearestTable(ErdNote n) {
    final layout = _layout;
    final schema = _schema;
    if (layout == null || schema == null) return null;
    final c = material.Offset(n.x + n.width / 2, n.y + n.height / 2);
    String? best;
    var bestDistance = double.infinity;
    for (final t in _visibleOf(schema).tables) {
      final d = (layout.rectOf(t).center - c).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = t.name;
      }
    }
    return best;
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

  material.Widget _noteWidget(ErdNote n) {
    final wb = context.workbench;
    final color = n.color == null ? null : _slotColor(n.color!);
    final lines = parseErdNote(n.text);
    final base = material.TextStyle(
        fontSize: 12, color: Theme.of(context).colorScheme.foreground);
    return material.Positioned(
      left: n.x,
      top: n.y,
      width: n.width,
      height: n.height,
      child: ContextMenu(
        items: [
          MenuButton(
            key: material.ValueKey('erd_note_edit_${n.id}'),
            onPressed: (_) => unawaited(_editNote(n)),
            child: const Text('Edit note…'),
          ),
          MenuButton(
            subMenu: [
              MenuButton(
                onPressed: (_) =>
                    _updateNote(n.id, (o) => o.copyWith(color: () => null)),
                child: const Text('None'),
              ),
              for (var i = 0; i < erdHeaderSlots.length; i++)
                MenuButton(
                  leading: material.Icon(material.Icons.circle,
                      size: 12, color: _slotColor(erdHeaderSlots[i])),
                  onPressed: (_) => _updateNote(
                      n.id, (o) => o.copyWith(color: () => erdHeaderSlots[i])),
                  child: Text('Colour ${i + 1}'),
                ),
            ],
            child: const Text('Colour'),
          ),
          if (n.attachedTo == null)
            MenuButton(
              key: material.ValueKey('erd_note_attach_${n.id}'),
              onPressed: (_) {
                final t = _nearestTable(n);
                if (t != null) {
                  _updateNote(n.id, (o) => o.copyWith(attachedTo: () => t));
                }
              },
              child: const Text('Attach to nearest table'),
            )
          else
            MenuButton(
              key: material.ValueKey('erd_note_detach_${n.id}'),
              onPressed: (_) =>
                  _updateNote(n.id, (o) => o.copyWith(attachedTo: () => null)),
              child: Text('Detach from ${n.attachedTo}'),
            ),
          MenuButton(
            key: material.ValueKey('erd_note_delete_${n.id}'),
            onPressed: (_) => _deleteNote(n.id),
            child: const Text('Delete note'),
          ),
        ],
        child: material.Stack(
          children: [
            material.Positioned.fill(
              child: material.MouseRegion(
                cursor: _draggingNote == n.id
                    ? material.SystemMouseCursors.grabbing
                    : material.SystemMouseCursors.grab,
                child: material.GestureDetector(
                  key: material.ValueKey('erd_note_${n.id}'),
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: (_) => setState(() => _draggingNote = n.id),
                  onPanUpdate: (d) => _noteDragMove(n.id, d.delta),
                  onPanEnd: (_) {
                    setState(() => _draggingNote = null);
                    _scheduleSave();
                  },
                  onPanCancel: () => setState(() => _draggingNote = null),
                  onDoubleTap: () => unawaited(_editNote(n)),
                  child: material.DecoratedBox(
                    decoration: material.BoxDecoration(
                      color: color == null
                          ? wb.surface
                          : material.Color.alphaBlend(
                              color.withValues(alpha: 0.18), wb.surface),
                      borderRadius: material.BorderRadius.circular(6),
                      border: material.Border.all(
                          color: color ?? wb.borderSubtle,
                          width: n.attachedTo == null ? 1 : 1.5),
                    ),
                    child: material.ClipRect(
                      child: material.Padding(
                        padding: const material.EdgeInsets.all(8),
                        child: material.SingleChildScrollView(
                          physics: const material.NeverScrollableScrollPhysics(),
                          child: material.Column(
                            crossAxisAlignment: material.CrossAxisAlignment.start,
                            children: [
                              for (final line in lines)
                                material.Text.rich(
                                  material.TextSpan(
                                    style: base,
                                    children: [
                                      if (line.bullet)
                                        const material.TextSpan(text: '•  '),
                                      for (final r in line.runs)
                                        material.TextSpan(
                                          text: r.text,
                                          style: r.bold
                                              ? const material.TextStyle(
                                                  fontWeight:
                                                      material.FontWeight.w700)
                                              : null,
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            material.Positioned(
              right: 0,
              bottom: 0,
              width: 16,
              height: 16,
              child: material.MouseRegion(
                cursor: material.SystemMouseCursors.resizeDownRight,
                child: material.GestureDetector(
                  key: material.ValueKey('erd_note_resize_${n.id}'),
                  dragStartBehavior: DragStartBehavior.down,
                  onPanUpdate: (d) => _noteResize(n.id, d.delta),
                  onPanEnd: (_) => _scheduleSave(),
                  child: material.Icon(material.Icons.drag_handle_rounded,
                      size: 12, color: wb.mutedForeground),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            comment: t.comment,
            columns: _collapsed.contains(t.name) || _detail == ErdDetail.names
                ? const []
                : [
                    for (final c in t.columns)
                      if (_detail == ErdDetail.all ||
                          c.isPrimaryKey ||
                          c.isForeignKey)
                        c,
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
    final computed = _compute(_visibleOf(schema));
    final current = _layout;
    setState(() {
      _setLayout(arrange || current == null
          ? computed
          : _withSaved(computed, ErdSavedLayout(positions: current.positions)));
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

  static Map<String, String> _junctionMap(ErdSchema schema) => {
        for (final t in schema.tables)
          if (t.isJunction)
            t.name: {
              for (final r in schema.relations)
                if (r.fromTable == t.name) r.toTable,
            }.join(' and '),
      };

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
    final p = _pickedRelation;
    if (p != null) {
      final on = table == p.fromTable || table == p.toTable;
      final column = table == p.fromTable
          ? p.fromColumn
          : (table == p.toTable ? p.toColumn : null);
      return (highlighted: on, faded: !on, column: column);
    }
    final highlighted = _isFocusedIn(_neighbours, focus, table);
    return (
      highlighted: highlighted,
      faded: _selected != null && !highlighted,
      column: null,
    );
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
      final scale = ErdExport.pngPixelRatio(_canvasSize(layout));
      final svg = ErdExport.toSvg(schema, layout,
          routes: _routes,
          headerFills: _headerFills(schema, const ErdSvgColors().card),
          groups: _svgGroups(layout, const ErdSvgColors().background),
          notes: _svgNotes(const ErdSvgColors().background,
              const ErdSvgColors().border));
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
        notes: _svgNotes(colors.background, colors.border));
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

  /// The toolbar's view switcher: All tables, the saved views, and the
  /// commands to save, rename and delete one.
  material.Widget _viewsMenu() {
    final wb = context.workbench;
    final active = _viewById(_activeView);
    return QueryaActionMenu<String>(
      items: [
        QueryaActionMenuItem(
          value: 'all',
          label: 'All tables',
          icon: active == null ? material.Icons.check : null,
        ),
        for (final v in _views)
          QueryaActionMenuItem(
            value: 'view:${v.id}',
            label: '${v.name} (${v.tables.length})',
            icon: v.id == active?.id ? material.Icons.check : null,
          ),
        const QueryaActionMenuItem(
          value: 'new',
          label: 'Save as new view…',
          icon: material.Icons.bookmark_add_outlined,
        ),
        if (active != null) ...[
          const QueryaActionMenuItem(
            value: 'rename',
            label: 'Rename view…',
            icon: material.Icons.edit_outlined,
          ),
          const QueryaActionMenuItem(
            value: 'delete',
            label: 'Delete view',
            icon: material.Icons.delete_outline_rounded,
          ),
        ],
      ],
      onSelected: (v) {
        switch (v) {
          case 'all':
            _switchView(null);
          case 'new':
            unawaited(_newView());
          case 'rename':
            unawaited(_renameView());
          case 'delete':
            _deleteView();
          default:
            if (v.startsWith('view:')) _switchView(v.substring(5));
        }
      },
      child: material.Padding(
        key: const material.ValueKey('erd_views'),
        padding: const material.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Icon(material.Icons.bookmarks_outlined,
                size: 16, color: wb.mutedForeground),
            const material.SizedBox(width: 6),
            Text(active?.name ?? 'All tables'),
            const material.SizedBox(width: 4),
            material.Icon(material.Icons.expand_more_rounded,
                size: 16, color: wb.mutedForeground),
          ],
        ),
      ),
    );
  }

  /// Group entries of a card's menu: group it (with the marked tables), add
  /// it to a group, take it out of its group.
  List<MenuItem> _groupMenu(String table) {
    final tables = {..._marked, table};
    final current = _groupOf(table);
    return [
      MenuButton(
        key: material.ValueKey('erd_menu_group_$table'),
        onPressed: (_) => unawaited(_newGroup(tables)),
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
  List<ErdSvgNote> _svgNotes(String backgroundHex, String borderHex) {
    final background = material.Color(
        0xFF000000 | int.parse(backgroundHex.substring(1), radix: 16));
    return [
      for (final n in _notes)
        ErdSvgNote(
          text: n.text,
          rect: material.Rect.fromLTWH(n.x, n.y, n.width, n.height),
          fill: ErdSvgColors.hex((n.color == null
                  ? background
                  : material.Color.alphaBlend(
                      _slotColor(n.color!).withValues(alpha: 0.18),
                      background))
              .toARGB32()),
          stroke: n.color == null
              ? borderHex
              : ErdSvgColors.hex(_slotColor(n.color!).toARGB32()),
        ),
    ];
  }

  /// Group frames for the SVG: the screen's tint over the export background.
  List<ErdSvgGroup> _svgGroups(ErdLayout layout, String backgroundHex) {
    final background = material.Color(
        0xFF000000 | int.parse(backgroundHex.substring(1), radix: 16));
    return [
      for (final g in _allGroups())
        if (layout.frameOf(g.tables) case final frame?)
          ErdSvgGroup(
            name: g.name,
            frame: frame,
            fill: ErdSvgColors.hex(material.Color.alphaBlend(
                    _slotColor(g.color).withValues(alpha: 0.06), background)
                .toARGB32()),
            stroke: ErdSvgColors.hex(_slotColor(g.color).toARGB32()),
          ),
    ];
  }

  /// A group's frame: a tinted box that takes no pointer, and its title,
  /// which drags the whole group and has the group's menu.
  List<material.Widget> _groupFrame(ErdGroup g, ErdLayout layout) {
    final frame = layout.frameOf(g.tables);
    if (frame == null) return const [];
    final color = _slotColor(g.color);
    final title = material.MouseRegion(
      cursor: _draggingGroup == g.id
          ? material.SystemMouseCursors.grabbing
          : material.SystemMouseCursors.grab,
      child: material.GestureDetector(
        key: material.ValueKey('erd_group_${g.id}'),
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) => _groupDragStart(g.id),
        onPanUpdate: (d) => _groupDragMove(g, d.delta),
        onPanEnd: (_) => _groupDragEnd(),
        onPanCancel: _groupDragEnd,
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Icon(
                g.isSchema
                    ? material.Icons.schema_outlined
                    : material.Icons.folder_open_rounded,
                size: 13,
                color: color),
            const material.SizedBox(width: 5),
            material.Flexible(
              child: Text(g.name,
                  maxLines: 1,
                  overflow: material.TextOverflow.ellipsis,
                  style: material.TextStyle(
                      fontSize: 12,
                      fontWeight: material.FontWeight.w600,
                      color: color)),
            ),
            if (g.note case final note?) ...[
              const material.SizedBox(width: 5),
              material.Tooltip(
                message: note,
                child: material.Icon(material.Icons.notes_rounded,
                    key: material.ValueKey('erd_group_note_${g.id}'),
                    size: 12,
                    color: color),
              ),
            ],
          ],
        ),
      ),
    );
    return [
      material.Positioned.fromRect(
        rect: frame,
        child: material.IgnorePointer(
          child: material.DecoratedBox(
            decoration: material.BoxDecoration(
              color: color.withValues(alpha: 0.05),
              borderRadius: material.BorderRadius.circular(12),
              border: material.Border.all(color: color.withValues(alpha: 0.55)),
            ),
          ),
        ),
      ),
      material.Positioned(
        left: frame.left + 10,
        top: frame.top + 3,
        width: max(0.0, frame.width - 20),
        height: ErdLayout.frameTitleHeight - 6,
        child: material.Align(
          alignment: material.Alignment.centerLeft,
          child: g.isSchema
              ? title
              : ContextMenu(
                  items: [
                    MenuButton(
                      key: material.ValueKey('erd_group_edit_${g.id}'),
                      onPressed: (_) => unawaited(_editGroup(g)),
                      child: const Text('Rename / note…'),
                    ),
                    MenuButton(
                      subMenu: [
                        for (var i = 0; i < erdHeaderSlots.length; i++)
                          MenuButton(
                            leading: material.Icon(material.Icons.circle,
                                size: 12, color: _slotColor(erdHeaderSlots[i])),
                            onPressed: (_) => _updateGroup(g.id,
                                (o) => o.copyWith(color: erdHeaderSlots[i])),
                            child: Text('Colour ${i + 1}'),
                          ),
                      ],
                      child: const Text('Colour'),
                    ),
                    MenuButton(
                      key: material.ValueKey('erd_group_ungroup_${g.id}'),
                      onPressed: (_) => _ungroup(g.id),
                      child: const Text('Ungroup'),
                    ),
                  ],
                  child: title,
                ),
        ),
      ),
    ];
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
      case _ExportAction.pdfA4:
        unawaited(_exportPdf(schema, layout, PdfPaper.a4));
      case _ExportAction.pdfA3:
        unawaited(_exportPdf(schema, layout, PdfPaper.a3));
      case _ExportAction.dbml:
        _save('$_fileStem.dbml',
            Uint8List.fromList(utf8.encode(_dbml(schema))));
      case _ExportAction.copyDbml:
        Clipboard.setData(ClipboardData(text: _dbml(schema)));
        showAppToast(
          context: context,
          message: 'DBML copied to the clipboard',
        );
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
                                painter: _RelationPainter(
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
                                    ..._groupMenu(t.name),
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
                        value: _ExportAction.pdfA4,
                        label: 'PDF (A4)',
                        icon: material.Icons.picture_as_pdf_outlined,
                      ),
                      QueryaActionMenuItem(
                        value: _ExportAction.pdfA3,
                        label: 'PDF (A3)',
                        icon: material.Icons.picture_as_pdf_outlined,
                      ),
                      QueryaActionMenuItem(
                        value: _ExportAction.dbml,
                        label: 'DBML (.dbml)',
                        icon: material.Icons.code_rounded,
                      ),
                      QueryaActionMenuItem(
                        value: _ExportAction.copyDbml,
                        label: 'Copy DBML',
                        icon: material.Icons.content_copy_rounded,
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
    this.marked = false,
    this.focusColumn,
    this.junctionOf,
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

  /// Marked for a group with Shift / Ctrl + click (#1282).
  final bool marked;

  /// The column of a picked relation on this card, shaded (#1281).
  final String? focusColumn;

  /// For a many-to-many link table: the tables it links.
  final String? junctionOf;
  final bool dragging;
  final material.VoidCallback? onOpen;
  final material.VoidCallback? onSelect;
  final void Function(bool inside) onHover;
  final material.VoidCallback onDragStart;
  final void Function(material.Offset delta) onDragMove;
  final material.VoidCallback onDragEnd;

  /// Everything a row knows, one fact a line.
  static String _columnTip(ErdColumn c) => [
        '${c.name}  ${c.type}',
        if (c.isPrimaryKey) 'Primary key',
        if (c.isForeignKey) 'Foreign key',
        c.isNullable ? 'Nullable' : 'Not null',
        if (c.isUnique && !c.isPrimaryKey) 'Unique',
        if (c.isIdentity) 'Generated (identity / auto increment)',
        if (c.defaultValue case final d?) 'Default: $d',
        if (c.domainBase case final b?) 'Domain over $b',
        if (c.enumValues.isNotEmpty) 'Values: ${_enumList(c.enumValues)}',
        if (c.comment case final n?) 'Note: $n',
      ].join('\n');

  /// At most [cap] labels, then how many more.
  static String _enumList(List<String> values, {int cap = 12}) =>
      values.length <= cap
          ? values.join(', ')
          : '${values.take(cap).join(', ')} (+${values.length - cap} more)';

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
                color: highlighted || marked ? wb.accent : wb.borderSubtle,
                width: marked ? 2.5 : (highlighted ? 1.5 : 1),
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
                        // The table's comment in the database (#1279).
                        if (table.comment case final note?) ...[
                          material.Tooltip(
                            message: note,
                            child: material.Icon(material.Icons.notes_rounded,
                                key: material.ValueKey(
                                    'erd_note_${table.name}'),
                                size: 13,
                                color: wb.mutedForeground),
                          ),
                          const material.SizedBox(width: 6),
                        ],
                        // A many-to-many link table (#1281).
                        if (junctionOf case final linked?) ...[
                          material.Tooltip(
                            message: 'Link table: many-to-many between $linked',
                            child: Text('M:N',
                                key: material.ValueKey(
                                    'erd_junction_${table.name}'),
                                style: material.TextStyle(
                                    fontSize: 9,
                                    fontWeight: material.FontWeight.w700,
                                    color: headerColor)),
                          ),
                          const material.SizedBox(width: 6),
                        ],
                        Text('${table.columns.length}',
                            style: material.TextStyle(
                                fontSize: 10, color: wb.mutedForeground)),
                      ],
                    ),
                  ),
                  for (final c in table.columns)
                    material.Container(
                      key: c.name == focusColumn
                          ? material.ValueKey(
                              'erd_focus_column_${table.name}_${c.name}')
                          : null,
                      height: ErdLayout.rowHeight,
                      // The column of a picked relation (#1281).
                      color: c.name == focusColumn
                          ? wb.accent.withValues(alpha: 0.14)
                          : null,
                      child: material.Tooltip(
                        message: _columnTip(c),
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
                              // The card is measured to fit both; at its
                              // maximum width the name gives way.
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
                                // Only a card at its maximum width has to
                                // share: then the type keeps half the row.
                                constraints: material.BoxConstraints(
                                    maxWidth: width >= ErdLayout.maxCardWidth
                                        ? (width - 56) / 2
                                        : double.infinity),
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
                              if (c.comment != null) ...[
                                const material.SizedBox(width: 3),
                                material.Icon(material.Icons.notes_rounded,
                                    key: material.ValueKey(
                                        'erd_note_${table.name}_${c.name}'),
                                    size: 10,
                                    color: wb.mutedForeground),
                              ],
                              // UQ / AI / DF after the type (#1277).
                              for (final b in c.badges) ...[
                                const material.SizedBox(width: 3),
                                Text(b,
                                    key: material.ValueKey(
                                        'erd_badge_${table.name}_${c.name}_$b'),
                                    style: material.TextStyle(
                                        fontSize: 9,
                                        fontWeight: material.FontWeight.w700,
                                        color: switch (b) {
                                          'EN' => palette.type5,
                                          'UQ' => palette.type3,
                                          'AI' => palette.type4,
                                          _ => wb.mutedForeground,
                                        })),
                              ],
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
    this.picked,
  });

  final List<ErdRoute> routes;
  final material.Color color;
  final material.Color highlight;

  /// Table whose relations are drawn on top in [highlight].
  final String? focus;

  /// A relation picked by a click: only it is drawn in [highlight] (#1281).
  final ErdRelation? picked;

  bool get _anyFocus => picked != null || focus != null;

  bool _focused(ErdRoute r) {
    final p = picked;
    if (p != null) return r.relation.sameAs(p);
    return focus != null &&
        (r.relation.fromTable == focus || r.relation.toTable == focus);
  }

  void _label(material.Canvas canvas, String text, material.Offset at,
      material.Color c) {
    final tp = material.TextPainter(
      text: material.TextSpan(
          text: text,
          style: material.TextStyle(
              fontSize: 10, color: c, fontWeight: material.FontWeight.w600)),
      textDirection: material.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - material.Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  void paint(material.Canvas canvas, material.Size size) {
    // Others first, focused on top.
    for (final pass in [false, true]) {
      for (final r in routes) {
        if (_focused(r) != pass || r.points.length < 2) continue;
        final paint = material.Paint()
          ..color = pass
              ? highlight
              : color.withValues(alpha: _anyFocus ? 0.35 : 0.85)
          ..style = material.PaintingStyle.stroke
          ..strokeWidth = pass ? 2 : 1.4
          ..strokeCap = material.StrokeCap.round
          ..strokeJoin = material.StrokeJoin.round;
        canvas.drawPath(roundedPath(r.points), paint);
        // FK end: a crow's foot ("many"), or a bar when the FK column is
        // unique on its own ("one", #1281).
        if (r.relation.oneToOne) {
          final (oa, ob) = ErdGeometry.oneBar(r.points[0], r.points[1]);
          canvas.drawLine(oa, ob, paint);
        } else {
          for (final (a, b)
              in ErdGeometry.crowFoot(r.points[0], r.points[1])) {
            canvas.drawLine(a, b, paint);
          }
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
        // Cardinality labels, as dbdiagram writes them.
        _label(canvas, r.relation.oneToOne ? '1' : '*',
            ErdGeometry.endLabel(r.points[0], r.points[1]), paint.color);
        _label(
            canvas,
            '1',
            ErdGeometry.endLabel(
                r.points.last, r.points[r.points.length - 2]),
            paint.color);
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
      old.focus != focus ||
      old.picked != picked;
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
