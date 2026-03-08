import 'dart:convert';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/database/redis_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Redis data explorer for a specific database.
/// Shows keys with search / SCAN pagination and a key editor.
class RedisExplorerView extends material.StatefulWidget {
  const RedisExplorerView({
    super.key,
    required this.connectionRow,
    required this.database,
  });

  final ConnectionRow connectionRow;
  final int database;

  @override
  material.State<RedisExplorerView> createState() => _RedisExplorerViewState();
}

class _RedisExplorerViewState extends material.State<RedisExplorerView> {
  RedisConnection? _connection;
  bool _loading = true;
  String? _error;

  // Keys list
  List<String> _keys = [];
  String _cursor = '0';
  bool _hasMore = false;
  String _searchPattern = '';
  final material.TextEditingController _searchCtrl = material.TextEditingController();

  // Selected key
  String? _selectedKey;
  String? _selectedKeyType;
  bool _showEditor = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(covariant RedisExplorerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.database != widget.database) {
      _disconnect();
      _connect();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _disconnect();
    super.dispose();
  }

  void _disconnect() {
    final c = _connection;
    _connection = null;
    if (c != null) c.disconnect();
  }

  Future<void> _connect() async {
    _disconnect();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _keys = [];
      _cursor = '0';
      _hasMore = false;
      _selectedKey = null;
      _showEditor = false;
    });
    try {
      final conn = RedisService.instance.createConnection(widget.connectionRow);
      await conn.connect();
      await conn.select(widget.database);
      if (!mounted) {
        conn.disconnect();
        return;
      }
      _connection = conn;
      await _scanKeys(reset: true);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _scanKeys({bool reset = false}) async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) return;
    if (reset) {
      _cursor = '0';
      _keys = [];
    }
    try {
      final pattern = _searchPattern.isNotEmpty ? '*$_searchPattern*' : null;
      final (nextCursor, keys) = await conn.scan(_cursor, pattern: pattern);
      if (!mounted) return;
      setState(() {
        _keys = reset ? keys : [..._keys, ...keys];
        _cursor = nextCursor;
        _hasMore = nextCursor != '0';
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _selectKey(String key) async {
    final conn = _connection;
    if (conn == null) return;
    try {
      final t = await conn.type(key);
      if (!mounted) return;
      setState(() {
        _selectedKey = key;
        _selectedKeyType = t;
        _showEditor = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _deleteKey(String key) async {
    final conn = _connection;
    if (conn == null) return;
    await conn.del([key]);
    if (!mounted) return;
    setState(() {
      _keys.remove(key);
      if (_selectedKey == key) {
        _selectedKey = null;
        _showEditor = false;
      }
    });
  }

  Future<void> _addKey(String key, String type, String value) async {
    final conn = _connection;
    if (conn == null) return;
    switch (type) {
      case 'string':
        await conn.set(key, value);
        break;
      case 'hash':
        await conn.hset(key, 'field1', value);
        break;
      case 'list':
        await conn.rpush(key, value);
        break;
      case 'set':
        await conn.sadd(key, value);
        break;
      case 'zset':
        await conn.zadd(key, 0, value);
        break;
    }
    await _scanKeys(reset: true);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return material.Center(
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            const material.SizedBox(
              width: 32, height: 32,
              child: material.CircularProgressIndicator(strokeWidth: 2),
            ),
            const Gap(16),
            const Text('Connecting...').muted().small(),
          ],
        ),
      );
    }

    if (_error != null) {
      return material.Center(
        child: material.Padding(
          padding: const material.EdgeInsets.all(32),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.Icon(material.Icons.error_outline_rounded, size: 48, color: cs.destructive),
              const Gap(16),
              const Text('Connection Error').large().semiBold(),
              const Gap(8),
              material.SelectableText(
                _error!,
                style: material.TextStyle(color: cs.mutedForeground, fontSize: 13),
              ),
              const Gap(24),
              OutlineButton(
                onPressed: _connect,
                leading: const material.Icon(material.Icons.refresh_rounded, size: 18),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return material.Container(
      color: cs.background,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          // Top bar
          _buildTopBar(context),
          const Divider(height: 1),
          // Content
          material.Expanded(
            child: _showEditor && _selectedKey != null
                ? _KeyEditorPanel(
                    connection: _connection!,
                    keyName: _selectedKey!,
                    keyType: _selectedKeyType ?? 'string',
                    onBack: () => setState(() => _showEditor = false),
                    onDeleted: () => _deleteKey(_selectedKey!),
                  )
                : _buildKeysList(context),
          ),
        ],
      ),
    );
  }

  material.Widget _buildTopBar(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return material.Container(
      height: 52,
      padding: const material.EdgeInsets.symmetric(horizontal: 16),
      decoration: material.BoxDecoration(
        color: cs.muted.withValues(alpha: 0.3),
      ),
      child: material.Row(
        children: [
          material.Icon(material.Icons.dns_rounded, size: 18, color: cs.primary),
          const Gap(10),
          Text('db${widget.database}').semiBold(),
          const Gap(8),
          Text('${_keys.length}${_hasMore ? '+' : ''} keys').muted().small(),
          const material.Spacer(),
          // Search
          material.SizedBox(
            width: 220,
            height: 32,
            child: material.TextField(
              controller: _searchCtrl,
              style: material.TextStyle(fontSize: 13, color: cs.foreground),
              decoration: material.InputDecoration(
                hintText: 'Search keys...',
                hintStyle: material.TextStyle(fontSize: 13, color: cs.mutedForeground),
                prefixIcon: material.Icon(material.Icons.search_rounded, size: 16, color: cs.mutedForeground),
                filled: true,
                fillColor: cs.background,
                contentPadding: const material.EdgeInsets.symmetric(horizontal: 12),
                border: material.OutlineInputBorder(
                  borderRadius: material.BorderRadius.circular(8),
                  borderSide: material.BorderSide(color: cs.border),
                ),
                enabledBorder: material.OutlineInputBorder(
                  borderRadius: material.BorderRadius.circular(8),
                  borderSide: material.BorderSide(color: cs.border.withValues(alpha: 0.5)),
                ),
                focusedBorder: material.OutlineInputBorder(
                  borderRadius: material.BorderRadius.circular(8),
                  borderSide: material.BorderSide(color: cs.primary),
                ),
              ),
              onSubmitted: (v) {
                _searchPattern = v.trim();
                _scanKeys(reset: true);
              },
            ),
          ),
          const Gap(8),
          OutlineButton(
            onPressed: () => _scanKeys(reset: true),
            size: ButtonSize.small,
            leading: const material.Icon(material.Icons.refresh_rounded, size: 16),
            child: const Text('Refresh'),
          ),
          const Gap(8),
          OutlineButton(
            onPressed: () => _showAddKeyDialog(context),
            size: ButtonSize.small,
            leading: const material.Icon(material.Icons.add_rounded, size: 16),
            child: const Text('Add Key'),
          ),
        ],
      ),
    );
  }

  void _showAddKeyDialog(material.BuildContext context) {
    final keyCtrl = material.TextEditingController();
    final valCtrl = material.TextEditingController();
    String selectedType = 'string';

    showDialog(
      context: context,
      builder: (ctx) {
        return material.StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Add Key'),
              content: material.SizedBox(
                width: 360,
                child: material.Column(
                  mainAxisSize: material.MainAxisSize.min,
                  children: [
                    material.TextField(
                      controller: keyCtrl,
                      decoration: const material.InputDecoration(labelText: 'Key name'),
                    ),
                    const Gap(12),
                    material.DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      decoration: const material.InputDecoration(labelText: 'Type'),
                      items: const [
                        material.DropdownMenuItem(value: 'string', child: material.Text('String')),
                        material.DropdownMenuItem(value: 'hash', child: material.Text('Hash')),
                        material.DropdownMenuItem(value: 'list', child: material.Text('List')),
                        material.DropdownMenuItem(value: 'set', child: material.Text('Set')),
                        material.DropdownMenuItem(value: 'zset', child: material.Text('Sorted Set')),
                      ],
                      onChanged: (v) => setDialogState(() => selectedType = v ?? 'string'),
                    ),
                    const Gap(12),
                    material.TextField(
                      controller: valCtrl,
                      decoration: const material.InputDecoration(labelText: 'Value'),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                material.TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const material.Text('Cancel'),
                ),
                material.ElevatedButton(
                  onPressed: () {
                    final key = keyCtrl.text.trim();
                    final val = valCtrl.text;
                    if (key.isNotEmpty) {
                      _addKey(key, selectedType, val);
                      Navigator.of(ctx).pop();
                    }
                  },
                  child: const material.Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  material.Widget _buildKeysList(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_keys.isEmpty) {
      return material.Center(
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Icon(material.Icons.vpn_key_off_rounded, size: 48, color: cs.mutedForeground),
            const Gap(16),
            const Text('No keys found').muted(),
          ],
        ),
      );
    }

    return material.ListView.builder(
      padding: const material.EdgeInsets.all(16),
      itemCount: _keys.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _keys.length) {
          // "Load more" button
          return material.Padding(
            padding: const material.EdgeInsets.symmetric(vertical: 8),
            child: material.Center(
              child: OutlineButton(
                onPressed: () => _scanKeys(),
                size: ButtonSize.small,
                child: const Text('Load more...'),
              ),
            ),
          );
        }

        final key = _keys[index];
        final isSelected = key == _selectedKey;

        return material.Padding(
          padding: const material.EdgeInsets.only(bottom: 2),
          child: material.Material(
            color: isSelected
                ? cs.primary.withValues(alpha: 0.1)
                : material.Colors.transparent,
            borderRadius: material.BorderRadius.circular(8),
            child: material.InkWell(
              onTap: () => _selectKey(key),
              borderRadius: material.BorderRadius.circular(8),
              child: material.Padding(
                padding: const material.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: material.Row(
                  children: [
                    material.Icon(material.Icons.vpn_key_rounded, size: 14, color: cs.mutedForeground),
                    const Gap(10),
                    material.Expanded(
                      child: material.Text(
                        key,
                        overflow: material.TextOverflow.ellipsis,
                        maxLines: 1,
                        style: material.TextStyle(
                          fontSize: 13,
                          color: cs.foreground,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    material.IconButton(
                      icon: material.Icon(
                        material.Icons.delete_outline_rounded,
                        size: 16,
                        color: cs.destructive.withValues(alpha: 0.7),
                      ),
                      onPressed: () => _deleteKey(key),
                      splashRadius: 16,
                      tooltip: 'Delete key',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Key Editor Panel ───────────────────────────────────────────────────────

class _KeyEditorPanel extends material.StatefulWidget {
  const _KeyEditorPanel({
    required this.connection,
    required this.keyName,
    required this.keyType,
    required this.onBack,
    required this.onDeleted,
  });

  final RedisConnection connection;
  final String keyName;
  final String keyType;
  final material.VoidCallback onBack;
  final material.VoidCallback onDeleted;

  @override
  material.State<_KeyEditorPanel> createState() => _KeyEditorPanelState();
}

class _KeyEditorPanelState extends material.State<_KeyEditorPanel> {
  bool _loading = true;
  String? _error;
  int _ttl = -1;

  // String
  String _stringValue = '';
  final material.TextEditingController _stringCtrl = material.TextEditingController();

  // Hash
  Map<String, String> _hashValue = {};

  // List
  List<String> _listValue = [];

  // Set
  List<String> _setValue = [];

  // Sorted set
  List<(String, double)> _zsetValue = [];

  @override
  void initState() {
    super.initState();
    _loadValue();
  }

  @override
  void didUpdateWidget(covariant _KeyEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyName != widget.keyName) {
      _loadValue();
    }
  }

  @override
  void dispose() {
    _stringCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadValue() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final conn = widget.connection;
      _ttl = await conn.ttl(widget.keyName);

      switch (widget.keyType) {
        case 'string':
          _stringValue = await conn.get(widget.keyName) ?? '';
          _stringCtrl.text = _stringValue;
          break;
        case 'hash':
          _hashValue = await conn.hgetall(widget.keyName);
          break;
        case 'list':
          final len = await conn.llen(widget.keyName);
          _listValue = await conn.lrange(widget.keyName, 0, len.clamp(0, 500) - 1);
          break;
        case 'set':
          _setValue = await conn.smembers(widget.keyName);
          break;
        case 'zset':
          final card = await conn.zcard(widget.keyName);
          _zsetValue = await conn.zrangeWithScores(widget.keyName, 0, card.clamp(0, 500) - 1);
          break;
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _saveString() async {
    try {
      await widget.connection.set(widget.keyName, _stringCtrl.text);
      if (mounted) {
        material.ScaffoldMessenger.of(context).showSnackBar(
          const material.SnackBar(content: material.Text('Saved'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _setTtl(int seconds) async {
    try {
      if (seconds > 0) {
        await widget.connection.expire(widget.keyName, seconds);
      } else {
        await widget.connection.persist(widget.keyName);
      }
      _ttl = await widget.connection.ttl(widget.keyName);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        // Header
        material.Container(
          padding: const material.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: material.BoxDecoration(
            color: cs.muted.withValues(alpha: 0.2),
            border: material.Border(
              bottom: material.BorderSide(color: cs.border.withValues(alpha: 0.3)),
            ),
          ),
          child: material.Row(
            children: [
              material.IconButton(
                icon: material.Icon(material.Icons.arrow_back_rounded, size: 18, color: cs.foreground),
                onPressed: widget.onBack,
                splashRadius: 16,
                tooltip: 'Back to keys',
              ),
              const Gap(8),
              material.Expanded(
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  mainAxisSize: material.MainAxisSize.min,
                  children: [
                    material.Text(
                      widget.keyName,
                      overflow: material.TextOverflow.ellipsis,
                      maxLines: 1,
                      style: material.TextStyle(
                        fontSize: 14,
                        fontWeight: material.FontWeight.w600,
                        color: cs.foreground,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Gap(2),
                    material.Row(
                      children: [
                        _TypeBadge(type: widget.keyType),
                        const Gap(12),
                        material.Text(
                          'TTL: ${_ttl == -1 ? 'No expiry' : _ttl == -2 ? 'Key missing' : '${_ttl}s'}',
                          style: material.TextStyle(fontSize: 11, color: cs.mutedForeground),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              OutlineButton(
                onPressed: _loadValue,
                size: ButtonSize.small,
                leading: const material.Icon(material.Icons.refresh_rounded, size: 16),
                child: const Text('Refresh'),
              ),
              const Gap(8),
              OutlineButton(
                onPressed: () => _showTtlDialog(context),
                size: ButtonSize.small,
                leading: const material.Icon(material.Icons.timer_outlined, size: 16),
                child: const Text('TTL'),
              ),
              const Gap(8),
              OutlineButton(
                onPressed: () {
                  widget.onDeleted();
                  widget.onBack();
                },
                size: ButtonSize.small,
                leading: material.Icon(material.Icons.delete_outline_rounded, size: 16, color: cs.destructive),
                child: Text('Delete', style: material.TextStyle(color: cs.destructive)),
              ),
            ],
          ),
        ),
        // Body
        material.Expanded(
          child: _loading
              ? const material.Center(
                  child: material.SizedBox(
                    width: 24, height: 24,
                    child: material.CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _error != null
                  ? material.Center(child: material.Text(_error!, style: material.TextStyle(color: cs.destructive)))
                  : _buildValueView(context),
        ),
      ],
    );
  }

  void _showTtlDialog(material.BuildContext context) {
    final ttlCtrl = material.TextEditingController(text: _ttl > 0 ? '$_ttl' : '');
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Set TTL'),
          content: material.SizedBox(
            width: 300,
            child: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                material.TextField(
                  controller: ttlCtrl,
                  decoration: const material.InputDecoration(
                    labelText: 'TTL in seconds (0 = persist)',
                  ),
                  keyboardType: material.TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            material.TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const material.Text('Cancel'),
            ),
            material.ElevatedButton(
              onPressed: () {
                final val = int.tryParse(ttlCtrl.text.trim()) ?? 0;
                _setTtl(val);
                Navigator.of(ctx).pop();
              },
              child: const material.Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  material.Widget _buildValueView(material.BuildContext context) {
    switch (widget.keyType) {
      case 'string':
        return _buildStringView(context);
      case 'hash':
        return _buildHashView(context);
      case 'list':
        return _buildListView(context);
      case 'set':
        return _buildSetView(context);
      case 'zset':
        return _buildZsetView(context);
      default:
        return material.Center(child: Text('Unsupported type: ${widget.keyType}').muted());
    }
  }

  material.Widget _buildStringView(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Try to format as JSON
    String? formattedJson;
    try {
      final parsed = jsonDecode(_stringCtrl.text);
      formattedJson = const JsonEncoder.withIndent('  ').convert(parsed);
    } catch (_) {
      // Not JSON, show as plain text
    }

    return material.Padding(
      padding: const material.EdgeInsets.all(16),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          material.Row(
            children: [
              const Text('Value').semiBold().small(),
              const material.Spacer(),
              OutlineButton(
                onPressed: _saveString,
                size: ButtonSize.small,
                leading: const material.Icon(material.Icons.save_outlined, size: 16),
                child: const Text('Save'),
              ),
            ],
          ),
          const Gap(8),
          material.Expanded(
            child: material.TextField(
              controller: _stringCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: material.TextAlignVertical.top,
              style: material.TextStyle(
                fontSize: 13,
                color: cs.foreground,
                fontFamily: 'monospace',
              ),
              decoration: material.InputDecoration(
                filled: true,
                fillColor: cs.card,
                border: material.OutlineInputBorder(
                  borderRadius: material.BorderRadius.circular(8),
                  borderSide: material.BorderSide(color: cs.border),
                ),
              ),
            ),
          ),
          if (formattedJson != null) ...[
            const Gap(8),
            const Text('Formatted JSON').muted().xSmall(),
          ],
        ],
      ),
    );
  }

  material.Widget _buildHashView(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = _hashValue.entries.toList();
    return material.ListView.builder(
      padding: const material.EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final e = entries[index];
        return material.Container(
          margin: const material.EdgeInsets.only(bottom: 4),
          padding: const material.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: material.BoxDecoration(
            color: cs.card,
            borderRadius: material.BorderRadius.circular(8),
            border: material.Border.all(color: cs.border.withValues(alpha: 0.3)),
          ),
          child: material.Row(
            children: [
              material.SizedBox(
                width: 180,
                child: material.Text(
                  e.key,
                  style: material.TextStyle(
                    fontSize: 13, color: cs.primary,
                    fontWeight: material.FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                  overflow: material.TextOverflow.ellipsis,
                ),
              ),
              const Gap(16),
              material.Expanded(
                child: material.Text(
                  e.value,
                  style: material.TextStyle(fontSize: 13, color: cs.foreground, fontFamily: 'monospace'),
                  overflow: material.TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              material.IconButton(
                icon: material.Icon(material.Icons.delete_outline_rounded, size: 16, color: cs.destructive.withValues(alpha: 0.7)),
                splashRadius: 16,
                onPressed: () async {
                  await widget.connection.hdel(widget.keyName, e.key);
                  _loadValue();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  material.Widget _buildListView(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return material.ListView.builder(
      padding: const material.EdgeInsets.all(16),
      itemCount: _listValue.length,
      itemBuilder: (context, index) {
        return material.Container(
          margin: const material.EdgeInsets.only(bottom: 4),
          padding: const material.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: material.BoxDecoration(
            color: cs.card,
            borderRadius: material.BorderRadius.circular(8),
            border: material.Border.all(color: cs.border.withValues(alpha: 0.3)),
          ),
          child: material.Row(
            children: [
              material.Text(
                '[$index]',
                style: material.TextStyle(fontSize: 12, color: cs.mutedForeground, fontFamily: 'monospace'),
              ),
              const Gap(12),
              material.Expanded(
                child: material.Text(
                  _listValue[index],
                  style: material.TextStyle(fontSize: 13, color: cs.foreground, fontFamily: 'monospace'),
                  overflow: material.TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  material.Widget _buildSetView(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return material.ListView.builder(
      padding: const material.EdgeInsets.all(16),
      itemCount: _setValue.length,
      itemBuilder: (context, index) {
        return material.Container(
          margin: const material.EdgeInsets.only(bottom: 4),
          padding: const material.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: material.BoxDecoration(
            color: cs.card,
            borderRadius: material.BorderRadius.circular(8),
            border: material.Border.all(color: cs.border.withValues(alpha: 0.3)),
          ),
          child: material.Row(
            children: [
              material.Expanded(
                child: material.Text(
                  _setValue[index],
                  style: material.TextStyle(fontSize: 13, color: cs.foreground, fontFamily: 'monospace'),
                  overflow: material.TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              material.IconButton(
                icon: material.Icon(material.Icons.delete_outline_rounded, size: 16, color: cs.destructive.withValues(alpha: 0.7)),
                splashRadius: 16,
                onPressed: () async {
                  await widget.connection.srem(widget.keyName, _setValue[index]);
                  _loadValue();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  material.Widget _buildZsetView(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return material.ListView.builder(
      padding: const material.EdgeInsets.all(16),
      itemCount: _zsetValue.length,
      itemBuilder: (context, index) {
        final (member, score) = _zsetValue[index];
        return material.Container(
          margin: const material.EdgeInsets.only(bottom: 4),
          padding: const material.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: material.BoxDecoration(
            color: cs.card,
            borderRadius: material.BorderRadius.circular(8),
            border: material.Border.all(color: cs.border.withValues(alpha: 0.3)),
          ),
          child: material.Row(
            children: [
              material.SizedBox(
                width: 80,
                child: material.Text(
                  score.toString(),
                  style: material.TextStyle(fontSize: 12, color: cs.primary, fontFamily: 'monospace'),
                ),
              ),
              const Gap(12),
              material.Expanded(
                child: material.Text(
                  member,
                  style: material.TextStyle(fontSize: 13, color: cs.foreground, fontFamily: 'monospace'),
                  overflow: material.TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              material.IconButton(
                icon: material.Icon(material.Icons.delete_outline_rounded, size: 16, color: cs.destructive.withValues(alpha: 0.7)),
                splashRadius: 16,
                onPressed: () async {
                  await widget.connection.zrem(widget.keyName, member);
                  _loadValue();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Type badge ──────────────────────────────────────────────────────────────

class _TypeBadge extends material.StatelessWidget {
  const _TypeBadge({required this.type});

  final String type;

  @override
  material.Widget build(material.BuildContext context) {
    final color = switch (type) {
      'string' => const material.Color(0xFF4CAF50),
      'hash' => const material.Color(0xFF2196F3),
      'list' => const material.Color(0xFFF9A825),
      'set' => const material.Color(0xFF9C27B0),
      'zset' => const material.Color(0xFFFF5722),
      _ => const material.Color(0xFF9E9E9E),
    };

    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: material.BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: material.BorderRadius.circular(4),
        border: material.Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: material.Text(
        type.toUpperCase(),
        style: material.TextStyle(fontSize: 10, fontWeight: material.FontWeight.w600, color: color),
      ),
    );
  }
}
