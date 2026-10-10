import 'package:querya_desktop/core/erd/erd_saved_layout.dart';

/// Operations on the user's table groups as functions of a list (#1362): each
/// returns a new list and never touches its argument, so the rules can be
/// tested without a widget tree.
abstract final class ErdGroupOps {
  /// The group [table] belongs to, if any.
  static ErdGroup? groupOf(List<ErdGroup> groups, String table) {
    for (final g in groups) {
      if (g.tables.contains(table)) return g;
    }
    return null;
  }

  /// [tables] out of every group but [except]; a group left empty goes.
  static List<ErdGroup> ungroupTables(
    List<ErdGroup> groups,
    Set<String> tables, {
    String? except,
  }) {
    final out = List.of(groups);
    for (var i = out.length - 1; i >= 0; i--) {
      final g = out[i];
      if (g.id == except || !g.tables.any(tables.contains)) continue;
      final left = [for (final t in g.tables) if (!tables.contains(t)) t];
      if (left.isEmpty) {
        out.removeAt(i);
      } else {
        out[i] = g.copyWith(tables: left);
      }
    }
    return out;
  }

  /// The number for the next default group name, `Group <n>`.
  static int nextNameNumber(List<ErdGroup> groups) {
    var n = groups.length + 1;
    while (groups.any((g) => g.name == 'Group $n')) {
      n++;
    }
    return n;
  }

  /// The number for the next group id, `g<n>`; it also picks the colour.
  static int nextIdNumber(List<ErdGroup> groups) {
    var id = 1;
    while (groups.any((g) => g.id == 'g$id')) {
      id++;
    }
    return id;
  }

  /// [groups] with [tables] taken out of their groups and put in a new group.
  /// [tableNames] is every table of the diagram in its order, so the group
  /// keeps that order.
  static List<ErdGroup> withNewGroup(
    List<ErdGroup> groups, {
    required Set<String> tables,
    required Iterable<String> tableNames,
    required String name,
    String? note,
  }) {
    final id = nextIdNumber(groups);
    return [
      ...ungroupTables(groups, tables),
      ErdGroup(
        id: 'g$id',
        name: name,
        note: note,
        color: erdHeaderSlots[(id - 1) % erdHeaderSlots.length],
        tables: [
          for (final t in tableNames)
            if (tables.contains(t)) t,
        ],
      ),
    ];
  }

  /// [groups] with [tables] taken out of the other groups and added to the
  /// group [id]. Unchanged apart from the ungrouping when [id] is unknown.
  static List<ErdGroup> addTables(
    List<ErdGroup> groups,
    String id,
    Set<String> tables,
  ) {
    final out = ungroupTables(groups, tables, except: id);
    final i = out.indexWhere((g) => g.id == id);
    if (i < 0) return out;
    final g = out[i];
    out[i] = g.copyWith(tables: [
      ...g.tables,
      for (final t in tables)
        if (!g.tables.contains(t)) t,
    ]);
    return out;
  }
}
