import 'dart:convert';
import 'dart:ui';

import 'package:querya_desktop/core/storage/local_db.dart';

/// How much of each card the diagram shows (#1278), as dbdiagram's detail
/// levels: the table name only, the key columns, or every column.
enum ErdDetail { names, keys, all }

/// What the user arranged on a diagram and wants back next time: card
/// positions, collapsed and hidden tables, the detail level and the viewport.
///
/// Tables are named as the diagram names them. Unknown keys in the stored JSON
/// are ignored, so later fields (colours, groups, notes) can be added.
class ErdSavedLayout {
  const ErdSavedLayout({
    this.positions = const {},
    this.collapsed = const {},
    this.hidden = const {},
    this.detail = ErdDetail.all,
    this.scale,
    this.translation,
    this.headerColors = const {},
    this.groups = const [],
  });

  final Map<String, Offset> positions;
  final Set<String> collapsed;
  final Set<String> hidden;
  final ErdDetail detail;

  /// Zoom and pan of the canvas; null when never saved (the view fits).
  final double? scale;
  final Offset? translation;

  /// Header colour picked per table: a palette slot name ([erdHeaderSlots]),
  /// not a colour, so it follows the theme.
  final Map<String, String> headerColors;

  /// Groups the user made (#1282). A table is in one group at most.
  final List<ErdGroup> groups;

  bool get isEmpty =>
      positions.isEmpty &&
      collapsed.isEmpty &&
      hidden.isEmpty &&
      detail == ErdDetail.all &&
      headerColors.isEmpty &&
      groups.isEmpty;

  /// The layout without the tables that no longer exist.
  ErdSavedLayout keepOnly(Set<String> tables) => ErdSavedLayout(
        positions: {
          for (final e in positions.entries)
            if (tables.contains(e.key)) e.key: e.value,
        },
        collapsed: collapsed.intersection(tables),
        hidden: hidden.intersection(tables),
        detail: detail,
        scale: scale,
        translation: translation,
        headerColors: {
          for (final e in headerColors.entries)
            if (tables.contains(e.key)) e.key: e.value,
        },
        groups: [
          for (final g in groups)
            if (g.tables.any(tables.contains))
              g.copyWith(tables: [
                for (final t in g.tables)
                  if (tables.contains(t)) t,
              ]),
        ],
      );

  Map<String, Object?> toJson() => {
        'v': 1,
        'positions': {
          for (final e in positions.entries)
            e.key: [_round(e.value.dx), _round(e.value.dy)],
        },
        'collapsed': collapsed.toList()..sort(),
        'hidden': hidden.toList()..sort(),
        'detail': detail.name,
        if (scale != null) 'scale': scale,
        if (translation != null)
          'translation': [_round(translation!.dx), _round(translation!.dy)],
        if (headerColors.isNotEmpty) 'headerColors': headerColors,
        if (groups.isNotEmpty) 'groups': [for (final g in groups) g.toJson()],
      };

  static double _round(double v) => (v * 10).roundToDouble() / 10;

  /// Null when [json] is not a layout this version can read.
  static ErdSavedLayout? fromJson(Object? json) {
    if (json is! Map) return null;
    Offset? offset(Object? v) {
      if (v is List && v.length == 2 && v[0] is num && v[1] is num) {
        return Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
      }
      return null;
    }

    Set<String> names(Object? v) =>
        v is List ? {for (final n in v) if (n is String) n} : <String>{};

    final positions = <String, Offset>{};
    final raw = json['positions'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final o = offset(e.value);
        if (e.key is String && o != null) positions[e.key as String] = o;
      }
    }
    final scale = json['scale'];
    final colors = <String, String>{};
    final rawColors = json['headerColors'];
    if (rawColors is Map) {
      for (final e in rawColors.entries) {
        if (e.key is String && erdHeaderSlots.contains(e.value)) {
          colors[e.key as String] = e.value as String;
        }
      }
    }
    final groups = <ErdGroup>[];
    final grouped = <String>{};
    final rawGroups = json['groups'];
    if (rawGroups is List) {
      for (final raw in rawGroups) {
        final g = ErdGroup.fromJson(raw);
        if (g == null || groups.any((o) => o.id == g.id)) continue;
        // A table in two groups keeps the first.
        final tables = [for (final t in g.tables) if (grouped.add(t)) t];
        if (tables.isNotEmpty) groups.add(g.copyWith(tables: tables));
      }
    }
    return ErdSavedLayout(
      positions: positions,
      collapsed: names(json['collapsed']),
      hidden: names(json['hidden']),
      detail: ErdDetail.values.firstWhere(
        (d) => d.name == json['detail'],
        // Layouts saved before #1278 had a keys-only flag.
        orElse: () => json['keysOnly'] == true ? ErdDetail.keys : ErdDetail.all,
      ),
      scale: scale is num && scale > 0 ? scale.toDouble() : null,
      translation: offset(json['translation']),
      headerColors: colors,
      groups: groups,
    );
  }

  String encode() => jsonEncode(toJson());

  static ErdSavedLayout? decode(String text) {
    try {
      return fromJson(jsonDecode(text));
    } catch (_) {
      return null;
    }
  }
}

/// A named set of tables drawn in a coloured frame, as dbdiagram's table
/// groups (#1282). [color] is a palette slot name ([erdHeaderSlots]).
///
/// The user's groups are saved with the layout; a schema group ([isSchema]) is
/// made by the view when the diagram spans several schemas and is not saved.
class ErdGroup {
  const ErdGroup({
    required this.id,
    required this.name,
    required this.color,
    required this.tables,
    this.note,
  });

  final String id;
  final String name;
  final String color;
  final String? note;
  final List<String> tables;

  static const schemaPrefix = 'schema:';

  bool get isSchema => id.startsWith(schemaPrefix);

  ErdGroup copyWith({
    String? name,
    String? color,
    List<String>? tables,
    String? Function()? note,
  }) =>
      ErdGroup(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        tables: tables ?? this.tables,
        note: note == null ? this.note : note(),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        if (note != null) 'note': note,
        'tables': tables,
      };

  /// Null unless [json] has an id, a name, a known colour and tables.
  static ErdGroup? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], name = json['name'], color = json['color'];
    final note = json['note'], tables = json['tables'];
    if (id is! String || id.isEmpty || id.startsWith(schemaPrefix)) {
      return null;
    }
    if (name is! String || name.trim().isEmpty) return null;
    if (color is! String || !erdHeaderSlots.contains(color)) return null;
    if (tables is! List) return null;
    final names = [
      for (final t in tables)
        if (t is String) t,
    ];
    if (names.isEmpty) return null;
    return ErdGroup(
      id: id,
      name: name,
      color: color,
      tables: names.toSet().toList(),
      note: note is String && note.trim().isNotEmpty ? note : null,
    );
  }
}

/// Groups by schema for the tables of [tables] that no group of [groups]
/// holds, when they span more than one schema; none otherwise. A table of the
/// current schema (no `schema.` prefix) gets no frame.
List<ErdGroup> erdSchemaGroups(
    Iterable<String> tables, List<ErdGroup> groups) {
  final schemas = <String, List<String>>{};
  for (final t in tables) {
    final dot = t.indexOf('.');
    schemas.putIfAbsent(dot <= 0 ? '' : t.substring(0, dot), () => []).add(t);
  }
  if (schemas.length < 2) return const [];
  final grouped = {for (final g in groups) ...g.tables};
  return [
    for (final e in schemas.entries)
      if (e.key.isNotEmpty)
        if ([for (final t in e.value) if (!grouped.contains(t)) t]
            case final free when free.isNotEmpty)
          ErdGroup(
            id: '${ErdGroup.schemaPrefix}${e.key}',
            name: e.key,
            color: erdSchemaSlot(e.key),
            tables: free,
          ),
  ];
}

/// Palette slots a card header can take: the theme's five chart colours.
const erdHeaderSlots = ['type1', 'type2', 'type3', 'type4', 'type5'];

/// The header slot of [table]: the one picked for it, else one per schema
/// (`sales.orders` and `sales.items` share a colour), else null for a table of
/// the current schema, which keeps the accent.
String? erdHeaderSlot(String table, Map<String, String> picked) {
  final chosen = picked[table];
  if (chosen != null) return chosen;
  final dot = table.indexOf('.');
  if (dot <= 0) return null;
  return erdSchemaSlot(table.substring(0, dot));
}

/// The palette slot of a schema: the same for every table in it.
String erdSchemaSlot(String schema) {
  var hash = 0;
  for (final unit in schema.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return erdHeaderSlots[hash % erdHeaderSlots.length];
}

/// Where a diagram's layout is kept between sessions.
abstract interface class ErdLayoutStore {
  Future<ErdSavedLayout?> read(ErdLayoutKey key);
  Future<void> write(ErdLayoutKey key, ErdSavedLayout layout);
}

/// One diagram: a connection and the database (and schema) it shows.
class ErdLayoutKey {
  const ErdLayoutKey({required this.connectionId, required this.scope});

  final int connectionId;

  /// The database, and the schema where the diagram is limited to one.
  final String scope;

  @override
  bool operator ==(Object other) =>
      other is ErdLayoutKey &&
      other.connectionId == connectionId &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(connectionId, scope);
}

/// Layouts in the app's own database (`erd_layouts`), removed with their
/// connection.
class LocalDbErdLayoutStore implements ErdLayoutStore {
  const LocalDbErdLayoutStore();

  @override
  Future<ErdSavedLayout?> read(ErdLayoutKey key) async {
    final text = await LocalDb.instance.readErdLayout(key.connectionId, key.scope);
    return text == null ? null : ErdSavedLayout.decode(text);
  }

  @override
  Future<void> write(ErdLayoutKey key, ErdSavedLayout layout) =>
      LocalDb.instance.writeErdLayout(key.connectionId, key.scope, layout.encode());
}
