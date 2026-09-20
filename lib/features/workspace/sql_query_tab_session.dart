import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/actions/sql_script_format.dart';
import 'package:querya_desktop/core/unsaved_work_registry.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';

/// A stateful query session inside an SQL workspace.
///
/// Each tab preserves its own query text buffer, execution results, status,
/// error state, and DML staging buffer independently.
class SqlQueryTabSession {
  SqlQueryTabSession({
    required this.id,
    required this.title,
    String? initialSql,
    this.filePath,
    double initialFraction = 0.65,
  })  : controller = material.TextEditingController(text: initialSql ?? ''),
        topFraction = material.ValueNotifier<double>(initialFraction) {
    UnsavedWorkRegistry.instance.register(
      this,
      () => isModified || (stagingBuffer?.isDirty ?? false),
    );
  }

  final String id;
  String title;
  String? filePath;
  final material.TextEditingController controller;
  final material.ValueNotifier<double> topFraction;

  bool running = false;
  String? error;
  List<String> columns = const [];
  List<List<String>> rows = const [];
  int? affectedRows;
  String? statusLine;
  DataGridStagingBuffer? stagingBuffer;
  String? lastExecutedSql;
  bool savingChanges = false;
  bool isModified = false;

  /// PK columns for SQL-grid Save, empty when Save is disabled.
  List<String> resultGridPrimaryKeys = const [];

  /// Column types from [getTableSchema] for DML literals, if resolved.
  Map<String, String>? resultGridColumnDataTypes;

  void formatSql() {
    final next = formatSqlScript(controller.text);
    controller.value = material.TextEditingValue(
      text: next,
      selection: material.TextSelection.collapsed(offset: next.length),
    );
    isModified = true;
  }

  void clearSql() {
    controller.clear();
    isModified = true;
  }

  void dispose() {
    UnsavedWorkRegistry.instance.unregister(this);
    controller.dispose();
    topFraction.dispose();
    stagingBuffer?.dispose();
  }
}
