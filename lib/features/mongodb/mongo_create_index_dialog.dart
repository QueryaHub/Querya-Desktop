import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

class _IndexFieldDraft {
  _IndexFieldDraft({String field = '', dynamic direction = 1})
      : controller = material.TextEditingController(text: field),
        direction = direction;

  final material.TextEditingController controller;
  dynamic direction;

  void dispose() {
    controller.dispose();
  }
}

/// Dialog for creating single, compound, unique, sparse, and TTL MongoDB indexes.
class MongoCreateIndexDialog extends material.StatefulWidget {
  const MongoCreateIndexDialog({
    super.key,
    required this.connection,
    required this.database,
    required this.collection,
    this.onCreateIndex,
  });

  final MongoConnection connection;
  final String database;
  final String collection;
  final Future<void> Function({
    required Map<String, dynamic> keys,
    String? name,
    bool unique,
    bool sparse,
    int? expireAfterSeconds,
  })? onCreateIndex;

  static Future<bool?> show({
    required material.BuildContext context,
    required MongoConnection connection,
    required String database,
    required String collection,
    Future<void> Function({
      required Map<String, dynamic> keys,
      String? name,
      bool unique,
      bool sparse,
      int? expireAfterSeconds,
    })? onCreateIndex,
  }) {
    return showAppDialog<bool>(
      context: context,
      builder: (ctx) => MongoCreateIndexDialog(
        connection: connection,
        database: database,
        collection: collection,
        onCreateIndex: onCreateIndex,
      ),
    );
  }

  @override
  material.State<MongoCreateIndexDialog> createState() =>
      _MongoCreateIndexDialogState();
}

class _MongoCreateIndexDialogState
    extends material.State<MongoCreateIndexDialog> {
  final List<_IndexFieldDraft> _fields = [
    _IndexFieldDraft(),
  ];

  bool _isUnique = false;
  bool _isSparse = false;
  final _ttlController = material.TextEditingController();
  final _nameController = material.TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    _ttlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _addField() {
    setState(() {
      _fields.add(_IndexFieldDraft());
    });
  }

  void _removeField(int index) {
    if (_fields.length <= 1) return;
    setState(() {
      final item = _fields.removeAt(index);
      item.dispose();
    });
  }

  String _computedIndexName() {
    final custom = _nameController.text.trim();
    if (custom.isNotEmpty) return custom;
    final parts = _fields
        .where((f) => f.controller.text.trim().isNotEmpty)
        .map((f) => '${f.controller.text.trim()}_${f.direction}')
        .toList();
    return parts.isEmpty ? 'new_index' : parts.join('_');
  }

  Future<void> _submit() async {
    final keys = <String, dynamic>{};
    for (final f in _fields) {
      final name = f.controller.text.trim();
      if (name.isEmpty) {
        setState(() => _error = 'All field names must be specified');
        return;
      }
      keys[name] = f.direction;
    }

    if (keys.isEmpty) {
      setState(() => _error = 'At least one index field is required');
      return;
    }

    int? expireAfterSeconds;
    final ttlText = _ttlController.text.trim();
    if (ttlText.isNotEmpty) {
      final parsed = int.tryParse(ttlText);
      if (parsed == null || parsed < 0) {
        setState(() => _error = 'TTL must be a positive integer in seconds');
        return;
      }
      expireAfterSeconds = parsed;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final customName = _nameController.text.trim();
      final indexName = customName.isNotEmpty ? customName : null;
      if (widget.onCreateIndex != null) {
        await widget.onCreateIndex!(
          keys: keys,
          name: indexName,
          unique: _isUnique,
          sparse: _isSparse,
          expireAfterSeconds: expireAfterSeconds,
        );
      } else {
        await MongoService.instance.createIndex(
          widget.connection,
          widget.database,
          widget.collection,
          keys: keys,
          name: indexName,
          unique: _isUnique,
          sparse: _isSparse,
          expireAfterSeconds: expireAfterSeconds,
        );
      }

      if (!mounted) return;
      showAppToast(
        context: context,
        message: 'Index created successfully',
        variant: AppToastVariant.success,
      );
      material.Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return QueryaModalDialog(
      title: const Text('Create Index'),
      description: Text('Collection: ${widget.collection}'),
      constraints: const material.BoxConstraints(maxWidth: 540),
      content: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            material.Container(
              padding: const material.EdgeInsets.all(10),
              decoration: material.BoxDecoration(
                color: cs.destructive.withValues(alpha: 0.1),
                borderRadius: material.BorderRadius.circular(6),
                border: material.Border.all(
                    color: cs.destructive.withValues(alpha: 0.3)),
              ),
              child: material.Text(
                _error!,
                style: material.TextStyle(
                  color: cs.destructive,
                  fontSize: 12.5,
                ),
              ),
            ),
            const Gap(12),
          ],
          // Index fields
          const Text('Index Keys').semiBold().small(),
          const Gap(6),
          for (int i = 0; i < _fields.length; i++) ...[
            material.Row(
              children: [
                material.Expanded(
                  flex: 3,
                  child: material.TextField(
                    controller: _fields[i].controller,
                    decoration: const material.InputDecoration(
                      hintText: 'Field name (e.g. email)',
                      isDense: true,
                      border: material.OutlineInputBorder(),
                      contentPadding: material.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    style: const material.TextStyle(fontSize: 13),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const Gap(8),
                material.SizedBox(
                  width: 150,
                  child: QueryaDropdown<dynamic>(
                    value: _fields[i].direction,
                    expandToParent: true,
                    items: const [
                      QueryaDropdownItem(value: 1, label: '1 (Asc)'),
                      QueryaDropdownItem(value: -1, label: '-1 (Desc)'),
                      QueryaDropdownItem(value: 'text', label: 'text'),
                      QueryaDropdownItem(value: '2dsphere', label: '2dsphere'),
                    ],
                    onSelected: (val) {
                      if (val != null) {
                        setState(() {
                          _fields[i].direction = val;
                        });
                      }
                    },
                  ),
                ),
                if (_fields.length > 1) ...[
                  const Gap(6),
                  QueryaIconButton(
                    icon: const material.Icon(
                      material.Icons.remove_circle_outline_rounded,
                    ),
                    tooltip: 'Remove Field',
                    density: QueryaIconButtonDensity.dense,
                    color: cs.destructive,
                    onPressed: () => _removeField(i),
                  ),
                ],
              ],
            ),
            const Gap(8),
          ],
          material.Align(
            alignment: material.Alignment.centerLeft,
            child: GhostButton(
              onPressed: _addField,
              size: ButtonSize.small,
              leading: const material.Icon(material.Icons.add_rounded, size: 14),
              child: const Text('Add Field (Compound)'),
            ),
          ),
          const Gap(16),
          const Divider(height: 1),
          const Gap(12),
          // Options
          const Text('Index Options').semiBold().small(),
          const Gap(8),
          material.Row(
            children: [
              material.InkWell(
                onTap: () => setState(() => _isUnique = !_isUnique),
                borderRadius: material.BorderRadius.circular(4),
                child: material.Padding(
                  padding: const material.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: material.Row(
                    mainAxisSize: material.MainAxisSize.min,
                    children: [
                      material.Checkbox(
                        value: _isUnique,
                        onChanged: (val) =>
                            setState(() => _isUnique = val == true),
                      ),
                      const Gap(4),
                      const Text('Unique').small(),
                    ],
                  ),
                ),
              ),
              const Gap(16),
              material.InkWell(
                onTap: () => setState(() => _isSparse = !_isSparse),
                borderRadius: material.BorderRadius.circular(4),
                child: material.Padding(
                  padding: const material.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: material.Row(
                    mainAxisSize: material.MainAxisSize.min,
                    children: [
                      material.Checkbox(
                        value: _isSparse,
                        onChanged: (val) =>
                            setState(() => _isSparse = val == true),
                      ),
                      const Gap(4),
                      const Text('Sparse').small(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const Gap(8),
          // TTL
          material.TextField(
            controller: _ttlController,
            keyboardType: material.TextInputType.number,
            decoration: const material.InputDecoration(
              labelText: 'TTL: Expire After Seconds (optional)',
              hintText: 'e.g. 86400 (24 hours)',
              isDense: true,
              border: material.OutlineInputBorder(),
              contentPadding: material.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
            ),
            style: const material.TextStyle(fontSize: 13),
          ),
          const Gap(12),
          // Index Name
          material.TextField(
            controller: _nameController,
            decoration: material.InputDecoration(
              labelText: 'Index Name (optional)',
              hintText: _computedIndexName(),
              isDense: true,
              border: const material.OutlineInputBorder(),
              contentPadding: const material.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
            ),
            style: const material.TextStyle(fontSize: 13),
          ),
        ],
      ),
      actions: [
        OutlineButton(
          onPressed: () => material.Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        PrimaryButton(
          onPressed: _submitting ? null : _submit,
          leading: _submitting
              ? const QueryaSpinner(size: QueryaSpinnerSize.sm)
              : const material.Icon(material.Icons.check_rounded, size: 16),
          child: Text(_submitting ? 'Creating...' : 'Create Index'),
        ),
      ],
    );
  }
}
