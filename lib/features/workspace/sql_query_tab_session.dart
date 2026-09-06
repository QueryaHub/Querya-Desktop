import 'package:flutter/material.dart' as material;
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
        topFraction = material.ValueNotifier<double>(initialFraction);

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

  void dispose() {
    controller.dispose();
    topFraction.dispose();
    stagingBuffer?.dispose();
  }
}
