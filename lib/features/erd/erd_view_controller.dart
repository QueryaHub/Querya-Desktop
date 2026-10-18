import 'dart:math' show max;
import 'dart:ui' show Offset, Size;

import 'package:querya_desktop/core/erd/erd_group_ops.dart';
import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_layout_engine.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_note_ops.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';

/// What the user has done to a diagram, apart from where the cards are:
/// the picked table and relation, marks, density, groups, notes and saved
/// views. No widgets and no layout geometry, so each rule is a plain method
/// that a unit test can call (#1690).
///
/// The view owns the layout, the routes and the viewport, and asks this for
/// the rest. Mutators change the state; the view decides when to rebuild and
/// to save.
class ErdViewController {
  /// The table being dragged.
  String? dragging;

  /// The table picked by a click or search: its edges stay highlighted.
  String? selected;

  /// A relation picked by a click on its edge (#1281): its two tables and
  /// columns are highlighted and its label stays until Esc.
  ErdRelation? pickedRelation;

  /// Tables marked with Shift / Ctrl / Cmd + click, to be grouped.
  final Set<String> marked = {};

  /// Density: only PK and FK columns, cards collapsed to their header, and
  /// tables hidden from the diagram.
  ErdDetail detail = ErdDetail.all;
  final Set<String> collapsed = {};
  final Set<String> hidden = {};

  /// Header colour picked per table (palette slot names, #1276).
  final Map<String, String> headerColors = {};

  /// The user's table groups, saved with the layout (#1282).
  final List<ErdGroup> groups = [];

  /// The group whose frame is being dragged by its title.
  String? draggingGroup;

  /// Sticky notes on the canvas, saved with the layout (#1283).
  final List<ErdNote> notes = [];
  String? draggingNote;

  /// Saved views of the diagram (#1284), the one the user is in, and the
  /// *All tables* state while a view is active.
  final List<ErdSavedView> views = [];
  String? activeView;
  ErdSavedLayout base = const ErdSavedLayout();

  /// Neighbours per table, for the focus of a hover or a pick.
  Map<String, Set<String>> neighbours = const {};

  /// Many-to-many link tables and what they link: `users and roles` (#1281).
  Map<String, String> junctions = const {};

  bool searchOpen = false;
  String query = '';

  // ---- Groups --------------------------------------------------------------

  /// The user's groups, then one per schema for the tables in none when the
  /// diagram spans several schemas.
  List<ErdGroup> allGroups(ErdSchema? schema) {
    if (schema == null) return List.of(groups);
    return [
      ...groups,
      ...erdSchemaGroups([for (final t in schema.tables) t.name], groups),
    ];
  }

  ErdGroup? groupOf(String table) => ErdGroupOps.groupOf(groups, table);

  void _replaceGroups(List<ErdGroup> next) {
    final copy = List.of(next);
    groups
      ..clear()
      ..addAll(copy);
  }

  /// Groups [tables] under [name], taking them out of other groups, and
  /// clears the marks. Returns the id of the new group.
  String createGroup({
    required Set<String> tables,
    required Iterable<String> tableNames,
    required String name,
    String? note,
  }) {
    _replaceGroups(ErdGroupOps.withNewGroup(
      groups,
      tables: tables,
      tableNames: tableNames,
      name: name,
      note: note,
    ));
    marked.clear();
    return groups.last.id;
  }

  /// Adds [tables] to the group [id]; the marks go when the group exists.
  void addToGroup(String id, Set<String> tables) {
    _replaceGroups(ErdGroupOps.addTables(groups, id, tables));
    if (groups.any((g) => g.id == id)) marked.clear();
  }

  /// Changes the group [id]; false when there is none.
  bool updateGroup(String id, ErdGroup Function(ErdGroup) change) {
    final i = groups.indexWhere((g) => g.id == id);
    if (i < 0) return false;
    groups[i] = change(groups[i]);
    return true;
  }

  void ungroup(String id) => groups.removeWhere((g) => g.id == id);

  void removeFromGroup(String table) =>
      _replaceGroups(ErdGroupOps.ungroupTables(groups, {table}));

  // ---- Marks, density, colours --------------------------------------------

  void toggleMarked(String table) {
    if (!marked.remove(table)) marked.add(table);
  }

  void toggleCollapsed(String table) {
    if (!collapsed.remove(table)) collapsed.add(table);
  }

  /// Hides [table] from the diagram.
  void hide(String table) {
    hidden.add(table);
    marked.remove(table);
    // A pick on a hidden table would leave every card faded.
    if (selected == table) selected = null;
  }

  /// [slot] null puts the table back to the default header colour.
  void setHeaderColor(String table, String? slot) {
    if (slot == null) {
      headerColors.remove(table);
    } else {
      headerColors[table] = slot;
    }
  }

  /// Applies the state a [ErdSavedLayout] holds: what is collapsed and hidden,
  /// the detail, groups and notes. Header colours belong to the diagram, so a
  /// view switch leaves them ([colours] false).
  void applyState(ErdSavedLayout s, {required bool colours}) {
    collapsed
      ..clear()
      ..addAll(s.collapsed);
    hidden
      ..clear()
      ..addAll(s.hidden);
    detail = s.detail;
    if (colours) {
      headerColors
        ..clear()
        ..addAll(s.headerColors);
    }
    groups
      ..clear()
      ..addAll(s.groups);
    notes
      ..clear()
      ..addAll(s.notes);
  }

  // ---- Notes ---------------------------------------------------------------

  void addNote(ErdNote note) => notes.add(note);

  bool updateNote(String id, ErdNote Function(ErdNote) change) {
    final i = notes.indexWhere((n) => n.id == id);
    if (i < 0) return false;
    notes[i] = change(notes[i]);
    return true;
  }

  void deleteNote(String id) => notes.removeWhere((n) => n.id == id);

  void moveNote(String id, Offset screenDelta, double scale) {
    final i = notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    notes[i] = ErdNoteOps.moved(notes[i], screenDelta, scale);
  }

  void resizeNote(String id, Offset screenDelta, double scale) {
    final i = notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    notes[i] = ErdNoteOps.resized(notes[i], screenDelta, scale);
  }

  /// Moves the notes attached to a table by what the table moved, from
  /// [before] to [after].
  void followTables(ErdLayout before, ErdLayout? after) {
    if (after == null || notes.every((n) => n.attachedTo == null)) return;
    for (var i = 0; i < notes.length; i++) {
      final t = notes[i].attachedTo;
      if (t == null) continue;
      final a = before.positions[t], b = after.positions[t];
      if (a == null || b == null || a == b) continue;
      final d = b - a;
      notes[i] = notes[i].copyWith(x: notes[i].x + d.dx, y: notes[i].y + d.dy);
    }
  }

  /// Canvas size: the cards and every note.
  Size canvasSize(ErdLayout layout) {
    var w = layout.size.width, h = layout.size.height;
    for (final n in notes) {
      w = max(w, n.x + n.width + ErdLayout.margin);
      h = max(h, n.y + n.height + ErdLayout.margin);
    }
    return Size(w, h);
  }

  // ---- Saved views ---------------------------------------------------------

  ErdSavedView? viewById(String? id) {
    for (final v in views) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// The id for the next view, `v<n>`.
  String nextViewId() {
    var n = 1;
    while (views.any((v) => v.id == 'v$n')) {
      n++;
    }
    return 'v$n';
  }

  /// Renames the view [id]; false when there is none.
  bool renameView(String id, String name) {
    final i = views.indexWhere((v) => v.id == id);
    if (i < 0) return false;
    views[i] = views[i].copyWith(name: name);
    return true;
  }

  void removeView(String id) => views.removeWhere((v) => v.id == id);

  // ---- Pick and focus ------------------------------------------------------

  /// A click on a card with no modifier: picks it and drops a picked relation.
  void pick(String name) {
    selected = name;
    pickedRelation = null;
  }

  /// A click on an edge: picks the relation, drops the table pick.
  void pickRelation(ErdRelation relation) {
    pickedRelation = relation;
    selected = null;
  }

  /// Drops the picks and the marks. False when there was nothing to drop.
  bool clearPicks() {
    if (selected == null && pickedRelation == null && marked.isEmpty) {
      return false;
    }
    selected = null;
    pickedRelation = null;
    marked.clear();
    return true;
  }

  /// What Esc does, one step per press: close the search, else drop the
  /// picked relation, else the marks, else the pick. The state is changed; the
  /// result says which step it was.
  ErdEscape escape() {
    if (searchOpen) {
      searchOpen = false;
      query = '';
      return ErdEscape.closedSearch;
    }
    if (pickedRelation != null) {
      pickedRelation = null;
      return ErdEscape.droppedRelation;
    }
    if (marked.isNotEmpty) {
      marked.clear();
      return ErdEscape.clearedMarks;
    }
    if (selected != null) {
      selected = null;
      return ErdEscape.clearedPick;
    }
    return ErdEscape.nothing;
  }

  /// The table the diagram focuses: the dragged one, then the picked one, then
  /// [hovered].
  String? currentFocus(String? hovered) => dragging ?? selected ?? hovered;

  /// How the card [table] looks for the focused table [focus]: highlighted
  /// when it is the focus or next to it, faded when something is picked and
  /// it is not, and the column of a picked relation.
  ({bool highlighted, bool faded, String? column}) cardFocusFor(
      String table, String? focus) {
    final p = pickedRelation;
    if (p != null) {
      final on = table == p.fromTable || table == p.toTable;
      final column = table == p.fromTable
          ? p.fromColumn
          : (table == p.toTable ? p.toColumn : null);
      return (highlighted: on, faded: !on, column: column);
    }
    final highlighted = ErdLayoutEngine.isFocusedIn(neighbours, focus, table);
    return (
      highlighted: highlighted,
      faded: selected != null && !highlighted,
      column: null,
    );
  }
}

/// Which step an Esc press took.
enum ErdEscape {
  closedSearch,
  droppedRelation,
  clearedMarks,
  clearedPick,
  nothing,
}
