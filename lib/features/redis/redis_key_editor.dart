import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// Viewer / editor for a single Redis key. Type-aware: string, hash,
/// list, set, zset.
class RedisKeyEditor extends material.StatefulWidget {
  const RedisKeyEditor({
    super.key,
    required this.connection,
    required this.database,
    required this.keyName,
    required this.keyType,
    this.onBack,
    this.onKeyDeleted,
  });

  final RedisConnection connection;
  final int database;
  final String keyName;
  final String keyType;
  final VoidCallback? onBack;
  final VoidCallback? onKeyDeleted;

  @override
  material.State<RedisKeyEditor> createState() => _RedisKeyEditorState();
}

class _RedisKeyEditorState extends material.State<RedisKeyEditor> {
  bool _loading = true;
  String? _error;
  String? _success;
  int _ttl = -1;

  // String value
  String? _stringValue;
  final _stringController = material.TextEditingController();

  // Hash value
  Map<String, String> _hashValue = {};

  // List value
  List<String> _listValue = [];

  // Set value
  List<String> _setValue = [];

  // Sorted set value
  List<(String, double)> _zsetValue = [];

  // For adding new items
  final _newFieldController = material.TextEditingController();
  final _newValueController = material.TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _stringController.dispose();
    _newFieldController.dispose();
    _newValueController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      await widget.connection.selectDatabase(widget.database);
      _ttl = await widget.connection.ttl(widget.keyName);

      switch (widget.keyType) {
        case 'string':
          _stringValue = await widget.connection.get(widget.keyName);
          _stringController.text = _stringValue ?? '';
        case 'hash':
          _hashValue = await widget.connection.hgetall(widget.keyName);
        case 'list':
          _listValue = await widget.connection.lrange(widget.keyName, 0, -1);
        case 'set':
          _setValue = await widget.connection.smembers(widget.keyName);
          _setValue.sort();
        case 'zset':
          _zsetValue =
              await widget.connection.zrangeWithScores(widget.keyName, 0, -1);
        default:
          _stringValue = await widget.connection.get(widget.keyName);
          _stringController.text = _stringValue ?? '';
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveString() async {
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.set(widget.keyName, _stringController.text);
      setState(() => _success = 'Value saved');
      _clearSuccessAfterDelay();
    } catch (e) {
      setState(() => _error = 'Save failed: $e');
    }
  }

  Future<void> _deleteKey() async {
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.del(widget.keyName);
      widget.onKeyDeleted?.call();
    } catch (e) {
      setState(() => _error = 'Delete failed: $e');
    }
  }

  Future<void> _setTtl(int seconds) async {
    try {
      await widget.connection.selectDatabase(widget.database);
      if (seconds > 0) {
        await widget.connection.expire(widget.keyName, seconds);
      } else {
        await widget.connection.persist(widget.keyName);
      }
      _ttl = await widget.connection.ttl(widget.keyName);
      setState(() {
        _success = seconds > 0 ? 'TTL set to $seconds seconds' : 'TTL removed';
      });
      _clearSuccessAfterDelay();
    } catch (e) {
      setState(() => _error = 'TTL failed: $e');
    }
  }

  // Hash operations
  Future<void> _hashSet(String field, String value) async {
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.hset(widget.keyName, field, value);
      await _load();
    } catch (e) {
      setState(() => _error = 'HSET failed: $e');
    }
  }

  Future<void> _hashDel(String field) async {
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.hdel(widget.keyName, field);
      await _load();
    } catch (e) {
      setState(() => _error = 'HDEL failed: $e');
    }
  }

  // List operations
  Future<void> _listPush(String value) async {
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.rpush(widget.keyName, value);
      await _load();
    } catch (e) {
      setState(() => _error = 'RPUSH failed: $e');
    }
  }

  // Set operations
  Future<void> _setAdd(String member) async {
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.sadd(widget.keyName, member);
      await _load();
    } catch (e) {
      setState(() => _error = 'SADD failed: $e');
    }
  }

  Future<void> _setRemove(String member) async {
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.srem(widget.keyName, member);
      await _load();
    } catch (e) {
      setState(() => _error = 'SREM failed: $e');
    }
  }

  // ZSet operations
  Future<void> _zsetAdd(String member, double score) async {
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.zadd(widget.keyName, score, member);
      await _load();
    } catch (e) {
      setState(() => _error = 'ZADD failed: $e');
    }
  }

  Future<void> _zsetRemove(String member) async {
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.zrem(widget.keyName, member);
      await _load();
    } catch (e) {
      setState(() => _error = 'ZREM failed: $e');
    }
  }

  void _clearSuccessAfterDelay() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _success = null);
    });
  }

  String _formatTtl(int ttl) {
    if (ttl == -1) return 'No expiry';
    if (ttl == -2) return 'Key missing';
    if (ttl < 60) return '${ttl}s';
    if (ttl < 3600) return '${(ttl / 60).toStringAsFixed(0)}m ${ttl % 60}s';
    if (ttl < 86400) {
      return '${(ttl / 3600).toStringAsFixed(0)}h ${((ttl % 3600) / 60).toStringAsFixed(0)}m';
    }
    return '${(ttl / 86400).toStringAsFixed(0)}d ${((ttl % 86400) / 3600).toStringAsFixed(0)}h';
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shadcnCs = shadcn.Theme.of(context).colorScheme;
    final palette = context.semanticPalette;

    if (_loading) {
      return material.Center(
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            const material.SizedBox(
              width: 32,
              height: 32,
              child: material.CircularProgressIndicator(strokeWidth: 2),
            ),
            const Gap(16),
            const Text('Loading key...').muted().small(),
          ],
        ),
      );
    }

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        // Status banners
        if (_error != null)
          material.Container(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            color: cs.destructive.withValues(alpha: 0.1),
            child: Row(
              children: [
                material.Icon(material.Icons.error_outline_rounded,
                    size: 16, color: cs.destructive),
                const Gap(8),
                material.Expanded(
                  child: Text(_error!,
                      style: material.TextStyle(
                          color: cs.destructive, fontSize: 13)),
                ),
                material.InkWell(
                  onTap: () => setState(() => _error = null),
                  child: material.Icon(material.Icons.close_rounded,
                      size: 16, color: cs.destructive),
                ),
              ],
            ),
          ),
        if (_success != null)
          material.Container(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            color: palette.success.withValues(alpha: 0.1),
            child: Row(
              children: [
                material.Icon(
                  material.Icons.check_circle_rounded,
                  size: 16,
                  color: palette.success,
                ),
                const Gap(8),
                Text(
                  _success!,
                  style:
                      material.TextStyle(color: palette.success, fontSize: 13),
                ),
              ],
            ),
          ),
        // Header
        _buildHeader(cs, shadcnCs),
        const Divider(height: 1),
        // Content
        material.Expanded(
          child: material.Padding(
            padding: const material.EdgeInsets.all(16),
            child: widget.keyType == 'string'
                ? material.SingleChildScrollView(
                    child: _buildContent(cs, shadcnCs),
                  )
                : _buildContent(cs, shadcnCs),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ColorScheme cs, shadcn.ColorScheme scs) {
    final typeCol = _typeColor(widget.keyType);
    return material.Container(
      padding:
          const material.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: material.BoxDecoration(
        color: scs.muted.withValues(alpha: 0.15),
      ),
      child: material.Row(
        children: [
          material.Icon(_typeIcon(widget.keyType), size: 18, color: typeCol),
          const Gap(8),
          material.Container(
            padding:
                const material.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: material.BoxDecoration(
              color: typeCol.withValues(alpha: 0.12),
              borderRadius: material.BorderRadius.circular(4),
            ),
            child: Text(
              widget.keyType.toUpperCase(),
              style: material.TextStyle(
                fontSize: 10,
                fontWeight: material.FontWeight.w600,
                color: typeCol,
              ),
            ),
          ),
          const Gap(10),
          material.Expanded(
            child: material.Text(
              widget.keyName,
              overflow: material.TextOverflow.ellipsis,
              maxLines: 1,
              style: material.TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                fontWeight: material.FontWeight.w500,
                color: cs.foreground,
              ),
            ),
          ),
          const Gap(8),
          // TTL badge
          material.Container(
            padding:
                const material.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: material.BoxDecoration(
              color: scs.muted.withValues(alpha: 0.3),
              borderRadius: material.BorderRadius.circular(6),
            ),
            child: Text(
              _formatTtl(_ttl),
              style: material.TextStyle(
                fontSize: 11,
                color: scs.mutedForeground,
              ),
            ),
          ),
          const Gap(8),
          // TTL button
          material.Tooltip(
            message: 'Set TTL',
            child: material.InkWell(
              onTap: () => _showTtlDialog(),
              borderRadius: material.BorderRadius.circular(4),
              child: material.Padding(
                padding: const material.EdgeInsets.all(4),
                child: material.Icon(material.Icons.timer_rounded,
                    size: 16, color: scs.mutedForeground),
              ),
            ),
          ),
          const Gap(4),
          // Refresh
          material.Tooltip(
            message: 'Refresh',
            child: material.InkWell(
              onTap: _load,
              borderRadius: material.BorderRadius.circular(4),
              child: material.Padding(
                padding: const material.EdgeInsets.all(4),
                child: material.Icon(material.Icons.refresh_rounded,
                    size: 16, color: scs.mutedForeground),
              ),
            ),
          ),
          const Gap(4),
          // Delete
          material.Tooltip(
            message: 'Delete key',
            child: material.InkWell(
              onTap: _deleteKey,
              borderRadius: material.BorderRadius.circular(4),
              child: material.Padding(
                padding: const material.EdgeInsets.all(4),
                child: material.Icon(material.Icons.delete_rounded,
                    size: 16, color: context.semanticPalette.destructive),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, shadcn.ColorScheme scs) {
    switch (widget.keyType) {
      case 'string':
        return _buildStringEditor(cs, scs);
      case 'hash':
        return _buildHashEditor(cs, scs);
      case 'list':
        return _buildListEditor(cs, scs);
      case 'set':
        return _buildSetEditor(cs, scs);
      case 'zset':
        return _buildZsetEditor(cs, scs);
      default:
        return _buildStringEditor(cs, scs);
    }
  }

  // ─── String ─────────────────────────────────────────────────────────────

  Widget _buildStringEditor(ColorScheme cs, shadcn.ColorScheme scs) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('Value').semiBold(),
            const Spacer(),
            PrimaryButton(
              onPressed: _saveString,
              size: ButtonSize.small,
              leading:
                  const material.Icon(material.Icons.save_rounded, size: 14),
              child: const Text('Save'),
            ),
          ],
        ),
        const Gap(8),
        material.Container(
          constraints: const material.BoxConstraints(minHeight: 200),
          decoration: material.BoxDecoration(
            border:
                material.Border.all(color: cs.border.withValues(alpha: 0.3)),
            borderRadius: material.BorderRadius.circular(8),
          ),
          child: material.TextField(
            controller: _stringController,
            maxLines: null,
            style: const material.TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            decoration: const material.InputDecoration(
              border: material.InputBorder.none,
              contentPadding: material.EdgeInsets.all(12),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Hash ───────────────────────────────────────────────────────────────

  Widget _buildHashEditor(ColorScheme cs, shadcn.ColorScheme scs) {
    final entries = _hashValue.entries.toList();
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        Text('Hash fields (${entries.length})').semiBold(),
        const Gap(8),
        material.Row(
          children: [
            material.Expanded(
              child: TextField(
                controller: _newFieldController,
                placeholder: const Text('Field'),
              ),
            ),
            const Gap(8),
            material.Expanded(
              child: TextField(
                controller: _newValueController,
                placeholder: const Text('Value'),
              ),
            ),
            const Gap(8),
            PrimaryButton(
              onPressed: () {
                final f = _newFieldController.text.trim();
                final v = _newValueController.text;
                if (f.isEmpty) return;
                _hashSet(f, v);
                _newFieldController.clear();
                _newValueController.clear();
              },
              size: ButtonSize.small,
              child: const Text('HSET'),
            ),
          ],
        ),
        const Gap(12),
        material.Expanded(
          child: entries.isEmpty
              ? material.Center(child: const Text('No fields').muted())
              : material.ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Gap(4),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _FieldRow(
                      field: entry.key,
                      value: entry.value,
                      onDelete: () => _hashDel(entry.key),
                      colorScheme: cs,
                      shadcnCs: scs,
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─── List ───────────────────────────────────────────────────────────────

  Widget _buildListEditor(ColorScheme cs, shadcn.ColorScheme scs) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        Text('List items (${_listValue.length})').semiBold(),
        const Gap(8),
        // Add item
        material.Row(
          children: [
            material.Expanded(
              child: TextField(
                controller: _newValueController,
                placeholder: const Text('New item'),
              ),
            ),
            const Gap(8),
            PrimaryButton(
              onPressed: () {
                final v = _newValueController.text;
                if (v.isEmpty) return;
                _listPush(v);
                _newValueController.clear();
              },
              size: ButtonSize.small,
              child: const Text('RPUSH'),
            ),
          ],
        ),
        const Gap(12),
        material.Expanded(
          child: _listValue.isEmpty
              ? material.Center(child: const Text('No items').muted())
              : material.ListView.separated(
                  itemCount: _listValue.length,
                  separatorBuilder: (_, __) => const Gap(4),
                  itemBuilder: (context, i) => _IndexedValueRow(
                    index: i,
                    value: _listValue[i],
                    colorScheme: cs,
                    shadcnCs: scs,
                  ),
                ),
        ),
      ],
    );
  }

  // ─── Set ────────────────────────────────────────────────────────────────

  Widget _buildSetEditor(ColorScheme cs, shadcn.ColorScheme scs) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        Text('Set members (${_setValue.length})').semiBold(),
        const Gap(8),
        // Add member
        material.Row(
          children: [
            material.Expanded(
              child: TextField(
                controller: _newValueController,
                placeholder: const Text('New member'),
              ),
            ),
            const Gap(8),
            PrimaryButton(
              onPressed: () {
                final v = _newValueController.text.trim();
                if (v.isEmpty) return;
                _setAdd(v);
                _newValueController.clear();
              },
              size: ButtonSize.small,
              child: const Text('SADD'),
            ),
          ],
        ),
        const Gap(12),
        material.Expanded(
          child: _setValue.isEmpty
              ? material.Center(child: const Text('No members').muted())
              : material.ListView.separated(
                  itemCount: _setValue.length,
                  separatorBuilder: (_, __) => const Gap(4),
                  itemBuilder: (context, index) => _MemberRow(
                    member: _setValue[index],
                    onDelete: () => _setRemove(_setValue[index]),
                    colorScheme: cs,
                    shadcnCs: scs,
                  ),
                ),
        ),
      ],
    );
  }

  // ─── Sorted Set ─────────────────────────────────────────────────────────

  Widget _buildZsetEditor(ColorScheme cs, shadcn.ColorScheme scs) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        Text('Sorted set (${_zsetValue.length})').semiBold(),
        const Gap(8),
        // Add member
        material.Row(
          children: [
            material.Expanded(
              flex: 2,
              child: TextField(
                controller: _newValueController,
                placeholder: const Text('Member'),
              ),
            ),
            const Gap(8),
            material.Expanded(
              child: TextField(
                controller: _newFieldController,
                placeholder: const Text('Score'),
              ),
            ),
            const Gap(8),
            PrimaryButton(
              onPressed: () {
                final m = _newValueController.text.trim();
                final s = double.tryParse(_newFieldController.text.trim());
                if (m.isEmpty || s == null) return;
                _zsetAdd(m, s);
                _newValueController.clear();
                _newFieldController.clear();
              },
              size: ButtonSize.small,
              child: const Text('ZADD'),
            ),
          ],
        ),
        const Gap(12),
        material.Expanded(
          child: _zsetValue.isEmpty
              ? material.Center(child: const Text('No members').muted())
              : material.ListView.separated(
                  itemCount: _zsetValue.length,
                  separatorBuilder: (_, __) => const Gap(4),
                  itemBuilder: (context, index) {
                    final (member, score) = _zsetValue[index];
                    return _ScoredMemberRow(
                      member: member,
                      score: score,
                      onDelete: () => _zsetRemove(member),
                      colorScheme: cs,
                      shadcnCs: scs,
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─── TTL dialog ─────────────────────────────────────────────────────────

  void _showTtlDialog() {
    showAppDialog<void>(
      context: context,
      builder: (ctx) => _RedisTtlDialogContent(
        initialTtl: _ttl,
        onApply: _setTtl,
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  Color _typeColor(String type) {
    final palette = context.semanticPalette;
    switch (type) {
      case 'string':
        return palette.type1;
      case 'hash':
        return palette.type4;
      case 'list':
        return palette.type2;
      case 'set':
        return palette.type3;
      case 'zset':
        return palette.type5;
      default:
        return palette.muted;
    }
  }

  material.IconData _typeIcon(String type) {
    switch (type) {
      case 'string':
        return material.Icons.text_fields_rounded;
      case 'hash':
        return material.Icons.tag_rounded;
      case 'list':
        return material.Icons.format_list_numbered_rounded;
      case 'set':
        return material.Icons.scatter_plot_rounded;
      case 'zset':
        return material.Icons.sort_rounded;
      default:
        return material.Icons.help_outline_rounded;
    }
  }
}

class _RedisTtlDialogContent extends material.StatefulWidget {
  const _RedisTtlDialogContent({
    required this.initialTtl,
    required this.onApply,
  });

  final int initialTtl;
  final Future<void> Function(int seconds) onApply;

  @override
  material.State<_RedisTtlDialogContent> createState() =>
      _RedisTtlDialogContentState();
}

class _RedisTtlDialogContentState
    extends material.State<_RedisTtlDialogContent> {
  late final material.TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = material.TextEditingController(
      text: widget.initialTtl > 0 ? '${widget.initialTtl}' : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    return AlertDialog(
      title: const Text('Set TTL'),
      content: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          const Text('Enter TTL in seconds (0 to remove)').muted().small(),
          const Gap(8),
          TextField(
            controller: _controller,
            placeholder: const Text('Seconds'),
          ),
        ],
      ),
      actions: [
        GhostButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        PrimaryButton(
          onPressed: () {
            final val = int.tryParse(_controller.text.trim());
            if (val != null) {
              widget.onApply(val);
            }
            Navigator.of(context).pop();
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

// ─── Shared row widgets ─────────────────────────────────────────────────────

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.value,
    required this.onDelete,
    required this.colorScheme,
    required this.shadcnCs,
  });

  final String field;
  final String value;
  final VoidCallback onDelete;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: material.BoxDecoration(
        color: colorScheme.card,
        borderRadius: material.BorderRadius.circular(6),
        border: material.Border.all(
            color: colorScheme.border.withValues(alpha: 0.3)),
      ),
      child: material.Row(
        children: [
          material.SizedBox(
            width: 160,
            child: material.Text(
              field,
              overflow: material.TextOverflow.ellipsis,
              style: material.TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: material.FontWeight.w600,
                color: shadcnCs.primary,
              ),
            ),
          ),
          const Gap(12),
          material.Expanded(
            child: material.SelectableText(
              value,
              style: material.TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colorScheme.foreground,
              ),
            ),
          ),
          const Gap(8),
          material.InkWell(
            onTap: onDelete,
            borderRadius: material.BorderRadius.circular(4),
            child: material.Padding(
              padding: const material.EdgeInsets.all(4),
              child: material.Icon(material.Icons.close_rounded,
                  size: 14, color: context.semanticPalette.destructive),
            ),
          ),
        ],
      ),
    );
  }
}

class _IndexedValueRow extends StatelessWidget {
  const _IndexedValueRow({
    required this.index,
    required this.value,
    required this.colorScheme,
    required this.shadcnCs,
  });

  final int index;
  final String value;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: material.BoxDecoration(
        color: colorScheme.card,
        borderRadius: material.BorderRadius.circular(6),
        border: material.Border.all(
            color: colorScheme.border.withValues(alpha: 0.3)),
      ),
      child: material.Row(
        children: [
          material.SizedBox(
            width: 40,
            child: Text(
              '$index',
              style: material.TextStyle(
                fontSize: 12,
                fontWeight: material.FontWeight.w600,
                color: shadcnCs.mutedForeground,
              ),
            ),
          ),
          const Gap(12),
          material.Expanded(
            child: material.SelectableText(
              value,
              style: material.TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colorScheme.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.onDelete,
    required this.colorScheme,
    required this.shadcnCs,
  });

  final String member;
  final VoidCallback onDelete;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: material.BoxDecoration(
        color: colorScheme.card,
        borderRadius: material.BorderRadius.circular(6),
        border: material.Border.all(
            color: colorScheme.border.withValues(alpha: 0.3)),
      ),
      child: material.Row(
        children: [
          material.Expanded(
            child: material.SelectableText(
              member,
              style: material.TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colorScheme.foreground,
              ),
            ),
          ),
          const Gap(8),
          material.InkWell(
            onTap: onDelete,
            borderRadius: material.BorderRadius.circular(4),
            child: material.Padding(
              padding: const material.EdgeInsets.all(4),
              child: material.Icon(material.Icons.close_rounded,
                  size: 14, color: context.semanticPalette.destructive),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoredMemberRow extends StatelessWidget {
  const _ScoredMemberRow({
    required this.member,
    required this.score,
    required this.onDelete,
    required this.colorScheme,
    required this.shadcnCs,
  });

  final String member;
  final double score;
  final VoidCallback onDelete;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: material.BoxDecoration(
        color: colorScheme.card,
        borderRadius: material.BorderRadius.circular(6),
        border: material.Border.all(
            color: colorScheme.border.withValues(alpha: 0.3)),
      ),
      child: material.Row(
        children: [
          material.Container(
            padding:
                const material.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: material.BoxDecoration(
              color: shadcnCs.muted.withValues(alpha: 0.3),
              borderRadius: material.BorderRadius.circular(4),
            ),
            child: Text(
              score.toStringAsFixed(score == score.roundToDouble() ? 0 : 2),
              style: material.TextStyle(
                fontSize: 11,
                fontWeight: material.FontWeight.w600,
                color: shadcnCs.primary,
              ),
            ),
          ),
          const Gap(12),
          material.Expanded(
            child: material.SelectableText(
              member,
              style: material.TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colorScheme.foreground,
              ),
            ),
          ),
          const Gap(8),
          material.InkWell(
            onTap: onDelete,
            borderRadius: material.BorderRadius.circular(4),
            child: material.Padding(
              padding: const material.EdgeInsets.all(4),
              child: material.Icon(material.Icons.close_rounded,
                  size: 14, color: context.semanticPalette.destructive),
            ),
          ),
        ],
      ),
    );
  }
}
