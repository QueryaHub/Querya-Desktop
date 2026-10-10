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

  bool get isEmpty =>
      positions.isEmpty &&
      collapsed.isEmpty &&
      hidden.isEmpty &&
      detail == ErdDetail.all &&
      headerColors.isEmpty;

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
  final schema = table.substring(0, dot);
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
