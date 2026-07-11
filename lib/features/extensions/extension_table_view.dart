import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/main_screen/results_tab.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

const _defaultPageSize = 200;

/// Paginated data browser for extension driver tables and views.
class ExtensionTableView extends material.StatefulWidget {
  const ExtensionTableView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.tableName,
    this.isView = false,
    this.pageSize = _defaultPageSize,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String tableName;
  final bool isView;
  final int pageSize;

  @override
  material.State<ExtensionTableView> createState() => _ExtensionTableViewState();
}

class _ExtensionTableViewState extends material.State<ExtensionTableView> {
  bool _loading = true;
  String? _error;
  List<String> _columns = [];
  List<List<String>> _rows = [];
  int _offset = 0;
  int? _totalRows;
  String? _statusLine;

  String get _qualifiedName =>
      '`${widget.database}`.`${widget.tableName}`';

  @override
  void initState() {
    super.initState();
    unawaited(_loadPage());
  }

  @override
  void didUpdateWidget(covariant ExtensionTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.database != widget.database ||
        oldWidget.tableName != widget.tableName) {
      _offset = 0;
      unawaited(_loadPage());
    }
  }

  Future<void> _loadPage({bool refreshCount = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (refreshCount || _totalRows == null) {
        final countResult = await ExtensionDriverSession.instance.query(
          widget.connectionRow,
          'SELECT count() AS cnt FROM $_qualifiedName',
        );
        if (countResult.rows.isNotEmpty && countResult.rows.first.isNotEmpty) {
          _totalRows = int.tryParse(countResult.rows.first.first);
        }
      }

      final dataResult = await ExtensionDriverSession.instance.query(
        widget.connectionRow,
        'SELECT * FROM $_qualifiedName LIMIT ${widget.pageSize} OFFSET $_offset',
      );

      if (!mounted) return;
      setState(() {
        _columns = dataResult.columns;
        _rows = dataResult.rows;
        _loading = false;
        final total = _totalRows;
        final shownFrom = _rows.isEmpty ? 0 : _offset + 1;
        final shownTo = _offset + _rows.length;
        _statusLine = total == null
            ? 'Showing $shownTo row(s).'
            : 'Rows $shownFrom–$shownTo of $total.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool get _canGoBack => _offset > 0;

  bool get _canGoForward {
    final total = _totalRows;
    if (total == null) return _rows.length >= widget.pageSize;
    return _offset + widget.pageSize < total;
  }

  void _previousPage() {
    if (!_canGoBack || _loading) return;
    _offset = (_offset - widget.pageSize).clamp(0, 1 << 30);
    unawaited(_loadPage());
  }

  void _nextPage() {
    if (!_canGoForward || _loading) return;
    _offset += widget.pageSize;
    unawaited(_loadPage());
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final kind = widget.isView ? 'View' : 'Table';

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Container(
          padding: const material.EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: material.BoxDecoration(
            color: theme.colorScheme.muted.withValues(alpha: 0.5),
            border: material.Border(
              bottom: material.BorderSide(
                color: theme.colorScheme.border.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: material.Row(
            children: [
              material.Expanded(
                child: Text('$kind · ${widget.database}.${widget.tableName}')
                    .semiBold()
                    .small(),
              ),
              OutlineButton(
                size: ButtonSize.small,
                onPressed: _loading ? null : () => _loadPage(refreshCount: true),
                child: const Text('Refresh'),
              ),
              const Gap(8),
              OutlineButton(
                size: ButtonSize.small,
                onPressed: _canGoBack && !_loading ? _previousPage : null,
                child: const Text('Previous'),
              ),
              const Gap(8),
              OutlineButton(
                size: ButtonSize.small,
                onPressed: _canGoForward && !_loading ? _nextPage : null,
                child: const Text('Next'),
              ),
            ],
          ),
        ),
        if (_statusLine != null)
          material.Padding(
            padding: const material.EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(_statusLine!).muted().xSmall(),
          ),
        const Divider(height: 1),
        material.Expanded(
          child: ResultsTab(
            columns: _columns,
            rows: _rows,
            errorMessage: _error,
            isLoading: _loading,
          ),
        ),
      ],
    );
  }
}
