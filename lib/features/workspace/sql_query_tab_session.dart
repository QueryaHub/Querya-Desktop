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
        _savedSql = initialSql ?? '',
        topFraction = material.ValueNotifier<double>(initialFraction) {
    controller.addListener(_onTextChanged);
    UnsavedWorkRegistry.instance.register(
      this,
      () => isDirty,
    );
  }

  final String id;
  String title;
  String? filePath;
  final material.TextEditingController controller;
  final material.ValueNotifier<double> topFraction;

  String _savedSql;
  bool running = false;
  String? error;
  List<String> columns = const [];
  List<List<String>> rows = const [];
  int? affectedRows;
  String? statusLine;
  DataGridStagingBuffer? stagingBuffer;
  String? lastExecutedSql;
  bool savingChanges = false;
  bool? _manualModified;

  /// True if the SQL query text has unsaved changes or was manually marked modified.
  bool get isModified =>
      _manualModified ??
      (filePath != null
          ? controller.text != _savedSql
          : controller.text.trim().isNotEmpty);

  set isModified(bool value) {
    _manualModified = value;
  }

  void _onTextChanged() {
    _manualModified = null;
  }

  /// True if the tab has uncommitted changes (modified text, unsaved query draft, or dirty staging buffer).
  bool get isDirty => isModified || (stagingBuffer?.isDirty ?? false);

  /// Marks the current query text as saved to disk or loaded from file.
  void markSaved({String? newFilePath}) {
    _savedSql = controller.text;
    _manualModified = false;
    if (newFilePath != null) {
      filePath = newFilePath;
    }
  }

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
  }

  void clearSql() {
    controller.clear();
  }

  void dispose() {
    controller.removeListener(_onTextChanged);
    UnsavedWorkRegistry.instance.unregister(this);
    controller.dispose();
    topFraction.dispose();
    stagingBuffer?.dispose();
  }
}
