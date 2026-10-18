import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/erd/erd_model.dart';

/// What a table card is built from outside its own focus: when all of it is
/// equal to the last build's, the card is reused as it is.
@immutable
class ErdCardInputs {
  const ErdCardInputs({
    required this.columns,
    required this.comment,
    required this.position,
    required this.width,
    required this.headerColor,
    required this.collapsed,
    required this.marked,
    required this.dragging,
    required this.junctionOf,
    required this.menuKey,
    required this.palette,
    required this.onOpenTable,
    required this.onOpenInSql,
    required this.onShowRelations,
  });

  final List<ErdColumn> columns;
  final String? comment;
  final material.Offset position;
  final double width;
  final material.Color headerColor;
  final bool collapsed;
  final bool marked;
  final bool dragging;
  final String? junctionOf;

  /// Hash of what the card's menu lists: the marked tables and the groups.
  final int menuKey;
  final Object palette;
  final Object? onOpenTable;
  final Object? onOpenInSql;
  final Object? onShowRelations;

  @override
  bool operator ==(Object other) {
    if (other is! ErdCardInputs) return false;
    if (columns.length != other.columns.length) return false;
    for (var i = 0; i < columns.length; i++) {
      if (!identical(columns[i], other.columns[i])) return false;
    }
    return comment == other.comment &&
        position == other.position &&
        width == other.width &&
        headerColor == other.headerColor &&
        collapsed == other.collapsed &&
        marked == other.marked &&
        dragging == other.dragging &&
        junctionOf == other.junctionOf &&
        menuKey == other.menuKey &&
        palette == other.palette &&
        onOpenTable == other.onOpenTable &&
        onOpenInSql == other.onOpenInSql &&
        onShowRelations == other.onShowRelations;
  }

  @override
  int get hashCode => Object.hash(columns.length, position, width, menuKey);
}
