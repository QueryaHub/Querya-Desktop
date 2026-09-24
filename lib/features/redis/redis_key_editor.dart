import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/features/workspace/destructive_query_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// Viewer / editor for a single Redis key. Type-aware: string, hash,
/// list, set, zset. Stream / module / unknown types are not GET/SET.
class RedisKeyEditor extends material.StatefulWidget {
  const RedisKeyEditor({
    super.key,
    required this.connection,
    required this.database,
    required this.keyName,
    required this.keyType,
    this.keyArg,
    this.controller,
    this.onBack,
    this.onKeyDeleted,
    this.onKeyRenamed,
    this.isReadOnly = false,
  });

  final RedisConnection connection;
  final int database;
  final String keyName;
  final String keyType;

  /// Wire key for GET/SET/DEL when [keyName] is only a UTF-8/hex label.
  final Object? keyArg;
  /// Optional controller for querying dirty-state from the parent widget.
  final RedisKeyEditorController? controller;
  final VoidCallback? onBack;
  final VoidCallback? onKeyDeleted;
  final ValueChanged<RedisBulkValue>? onKeyRenamed;
  final bool isReadOnly;

  @override
  material.State<RedisKeyEditor> createState() => _RedisKeyEditorState();
}

/// Controller that lets the parent widget ask whether it is safe to navigate
/// away from this editor (i.e. no unsaved string value edits).
class RedisKeyEditorController {
  _RedisKeyEditorState? _state;

  /// Returns `true` when navigation is safe (not dirty, or user confirmed
  /// discarding their edits).
  Future<bool> canNavigateAway() =>
      _state?._confirmDiscardStringEdits() ?? Future.value(true);

  void _attach(_RedisKeyEditorState state) => _state = state;
  void _detach(_RedisKeyEditorState state) {
    if (_state == state) _state = null;
  }
}

class _RedisKeyEditorState extends material.State<RedisKeyEditor> {
  bool _loading = true;
  String? _error;
  String? _success;
  int _ttl = -1;

  // String value
  RedisBulkValue? _stringValue;
  final _stringController = material.TextEditingController();
  /// The text that was last loaded from the server (null = not yet loaded).
  String? _savedStringText;

  // Hash value
  Map<RedisBulkValue, RedisBulkValue> _hashValue = {};

  // List value
  List<RedisBulkValue> _listValue = [];

  // Set value
  List<RedisBulkValue> _setValue = [];

  // Sorted set value
  List<(RedisBulkValue, double)> _zsetValue = [];

  int _collectionTotal = 0;
  int _scanCursor = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  late String _effectiveType;
  late String _currentKeyName;
  Object? _currentKeyArg;

  // For adding new items
  final _newFieldController = material.TextEditingController();
  final _newValueController = material.TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _currentKeyName = widget.keyName;
    _currentKeyArg = widget.keyArg;
    _effectiveType = _normalizedType(widget.keyType);
    _load();
  }

  @override
  void didUpdateWidget(covariant RedisKeyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyName != widget.keyName ||
        oldWidget.keyArg != widget.keyArg) {
      _currentKeyName = widget.keyName;
      _currentKeyArg = widget.keyArg;
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _stringController.dispose();
    _newFieldController.dispose();
    _newValueController.dispose();
    super.dispose();
  }

  Object get _cmdKey => _currentKeyArg ?? _currentKeyName;

  bool get _stringIsBinary =>
      _effectiveType == 'string' &&
      _stringValue != null &&
      !_stringValue!.isUtf8;

  /// True when the user has unsaved edits in the string text field.
  bool get _isStringDirty =>
      _effectiveType == 'string' &&
      !_stringIsBinary &&
      _savedStringText != null &&
      _stringController.text != _savedStringText;

  /// Shows a discard-confirmation dialog if there are unsaved string edits.
  /// Returns `true` when it is safe to proceed (either not dirty or confirmed).
  Future<bool> _confirmDiscardStringEdits() async {
    if (!_isStringDirty) return true;
    if (!mounted) return false;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
          'You have unsaved edits to this string value. '
          'Do you want to discard them?',
        ),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  String _normalizedType(String type) {
    final t = type.trim().toLowerCase();
    if (t.isEmpty) return 'unknown';
    return t;
  }

  Future<String> _resolveType() async {
    final incoming = _normalizedType(widget.keyType);
    if (incoming != 'unknown') return incoming;
    try {
      final resolved = _normalizedType(
        await widget.connection.keyType(_cmdKey),
      );
      if (resolved == 'none' || resolved == 'unknown') return 'unknown';
      return resolved;
    } catch (_) {
      return 'unknown';
    }
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
      _ttl = await widget.connection.ttl(_cmdKey);
      _effectiveType = await _resolveType();

      switch (_effectiveType) {
        case 'string':
          _stringValue = await widget.connection.get(_cmdKey);
          final loaded = _stringValue?.text ?? '';
          _stringController.text = loaded;
          _savedStringText = loaded;
        case 'hash':
        case 'list':
        case 'set':
        case 'zset':
          _collectionTotal = await widget.connection.keySize(
            _cmdKey,
            _effectiveType,
          );
          _scanCursor = 0;
          _hashValue = {};
          _listValue = [];
          _setValue = [];
          _zsetValue = [];
          _hasMore = false;
          await _loadMore(reset: true);
        default:
          _stringValue = null;
          _stringController.text = '';
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

  int get _loadedCount => switch (_effectiveType) {
        'hash' => _hashValue.length,
        'list' => _listValue.length,
        'set' => _setValue.length,
        'zset' => _zsetValue.length,
        _ => 0,
      };

  String _collectionHeading(String noun) {
    if (_collectionTotal > 0) {
      return '$noun ($_loadedCount / $_collectionTotal)';
    }
    return '$noun ($_loadedCount)';
  }

  Widget _loadMoreTile() {
    return material.Padding(
      padding: const material.EdgeInsets.only(top: 12),
      child: material.Center(
        child: OutlineButton(
          onPressed: _loadingMore ? null : () => _loadMore(),
          size: ButtonSize.small,
          child: _loadingMore
              ? const Text('Loading...')
              : Text('Load more ($_loadedCount / $_collectionTotal)'),
        ),
      ),
    );
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loadingMore) return;
    if (!reset && mounted) setState(() => _loadingMore = true);
    try {
      await widget.connection.selectDatabase(widget.database);
      switch (_effectiveType) {
        case 'hash':
          if (reset) {
            _scanCursor = 0;
            _hashValue = {};
          }
          final (next, page) = await widget.connection.hscan(
            _cmdKey,
            cursor: _scanCursor,
            count: redisCollectionPageSize,
          );
          _hashValue.addAll(page);
          _scanCursor = next;
          _hasMore = next != 0;
        case 'list':
          if (reset) _listValue = [];
          final start = _listValue.length;
          final chunk = await widget.connection.lrange(
            _cmdKey,
            start,
            start + redisCollectionPageSize - 1,
          );
          _listValue.addAll(chunk);
          _hasMore = _listValue.length < _collectionTotal;
        case 'set':
          if (reset) {
            _scanCursor = 0;
            _setValue = [];
          }
          final (next, members) = await widget.connection.sscan(
            _cmdKey,
            cursor: _scanCursor,
            count: redisCollectionPageSize,
          );
          _setValue.addAll(members);
          _scanCursor = next;
          _hasMore = next != 0;
        case 'zset':
          if (reset) _zsetValue = [];
          final start = _zsetValue.length;
          final chunk = await widget.connection.zrangeWithScores(
            _cmdKey,
            start,
            start + redisCollectionPageSize - 1,
          );
          _zsetValue.addAll(chunk);
          _hasMore = _zsetValue.length < _collectionTotal;
      }
      if (!mounted) return;
      setState(() => _loadingMore = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = 'Load failed: $e';
      });
    }
  }

  Future<void> _saveString() async {
    if (widget.isReadOnly) return;
    if (_effectiveType != 'string' || _stringIsBinary) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.set(
        _cmdKey,
        _stringController.text,
        keepTtl: true,
      );
      if (!mounted) return;
      setState(() => _success = 'Value saved');
      _clearSuccessAfterDelay();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Save failed: $e');
    }
  }

  Future<void> _renameKey() async {
    if (widget.isReadOnly) return;
    final targetName = await showAppDialog<String>(
      context: context,
      builder: (ctx) => _RedisRenameDialogContent(
        initialKey: _currentKeyName,
      ),
    );
    if (targetName == null || targetName.trim().isEmpty) return;
    final trimmedNew = targetName.trim();
    if (trimmedNew == _currentKeyName) return;

    try {
      await widget.connection.selectDatabase(widget.database);
      final exists = (await widget.connection.exists(trimmedNew)) > 0;
      if (exists && mounted) {
        final confirmed = await confirmDestructiveAction(
          context: context,
          type: DestructiveSqlType.redisRename,
          targetName: trimmedNew,
          commandPreview: 'RENAME $_currentKeyName $trimmedNew',
          connectionName: widget.connection.name,
        );
        if (!mounted || !confirmed) return;
      }

      await widget.connection.rename(_cmdKey, trimmedNew);
      if (!mounted) return;
      final newBulk = RedisBulkValue.fromReply(trimmedNew);
      setState(() {
        _currentKeyName = trimmedNew;
        _currentKeyArg = trimmedNew;
        _success = 'Key renamed to $trimmedNew';
      });
      _clearSuccessAfterDelay();
      widget.onKeyRenamed?.call(newBulk);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Rename failed: $e');
      }
    }
  }

  Future<void> _deleteKey() async {
    if (widget.isReadOnly) return;
    final confirmed = await confirmDestructiveAction(
      context: context,
      type: DestructiveSqlType.redisDel,
      targetName: '$_currentKeyName ($_effectiveType)',
      commandPreview: 'DEL $_currentKeyName',
      connectionName: widget.connection.name,
    );
    if (!mounted || !confirmed) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.del(_cmdKey);
      widget.onKeyDeleted?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Delete failed: $e');
    }
  }

  Future<void> _setTtl(int seconds) async {
    if (widget.isReadOnly) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      if (seconds > 0) {
        await widget.connection.expire(_cmdKey, seconds);
      } else {
        await widget.connection.persist(_cmdKey);
      }
      _ttl = await widget.connection.ttl(_cmdKey);
      if (!mounted) return;
      setState(() {
        _success = seconds > 0 ? 'TTL set to $seconds seconds' : 'TTL removed';
      });
      _clearSuccessAfterDelay();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'TTL failed: $e');
    }
  }

  // Hash operations
  Future<void> _hashSet(String field, String value) async {
    if (widget.isReadOnly) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.hset(_cmdKey, field, value);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'HSET failed: $e');
    }
  }

  Future<void> _hashDel(RedisBulkValue field) async {
    if (widget.isReadOnly) return;
    final confirmed = await confirmDestructiveAction(
      context: context,
      type: DestructiveSqlType.redisHdel,
      targetName: field.label,
      commandPreview: 'HDEL ${widget.keyName} ${field.label}',
      connectionName: widget.connection.name,
    );
    if (!mounted || !confirmed) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.hdel(_cmdKey, field);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'HDEL failed: $e');
    }
  }

  // List operations
  Future<void> _listPush(String value) async {
    if (widget.isReadOnly) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.rpush(_cmdKey, value);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'RPUSH failed: $e');
    }
  }

  Future<void> _listSet(int index, String newValue) async {
    if (widget.isReadOnly) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.lset(_cmdKey, index, newValue);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'LSET failed: $e');
    }
  }

  Future<void> _listRemove(int index, RedisBulkValue item) async {
    if (widget.isReadOnly) return;
    final confirmed = await confirmDestructiveAction(
      context: context,
      type: DestructiveSqlType.redisLrem,
      targetName: '[$index] ${item.label}',
      commandPreview: 'LREM $_currentKeyName 1 ${item.label}',
      connectionName: widget.connection.name,
    );
    if (!mounted || !confirmed) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      final sentinel =
          '__QUERYA_DEL_${DateTime.now().microsecondsSinceEpoch}__';
      await widget.connection.lset(_cmdKey, index, sentinel);
      await widget.connection.lrem(_cmdKey, 1, sentinel);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'LREM failed: $e');
    }
  }

  // Set operations
  Future<void> _setAdd(String member) async {
    if (widget.isReadOnly) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.sadd(_cmdKey, member);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'SADD failed: $e');
    }
  }

  Future<void> _setRemove(RedisBulkValue member) async {
    if (widget.isReadOnly) return;
    final confirmed = await confirmDestructiveAction(
      context: context,
      type: DestructiveSqlType.redisSrem,
      targetName: member.label,
      commandPreview: 'SREM ${widget.keyName} ${member.label}',
      connectionName: widget.connection.name,
    );
    if (!mounted || !confirmed) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.srem(_cmdKey, member);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'SREM failed: $e');
    }
  }

  // ZSet operations
  Future<void> _zsetAdd(String member, double score) async {
    if (widget.isReadOnly) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.zadd(_cmdKey, score, member);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'ZADD failed: $e');
    }
  }

  Future<void> _zsetRemove(RedisBulkValue member) async {
    if (widget.isReadOnly) return;
    final confirmed = await confirmDestructiveAction(
      context: context,
      type: DestructiveSqlType.redisZrem,
      targetName: member.label,
      commandPreview: 'ZREM ${widget.keyName} ${member.label}',
      connectionName: widget.connection.name,
    );
    if (!mounted || !confirmed) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.zrem(_cmdKey, member);
      await _load();
    } catch (e) {
      if (!mounted) return;
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
        if (_collectionTotal >= redisLargeCollectionWarnAt)
          material.Container(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: Text(
              'Large key ($_collectionTotal members). Loading in pages of $redisCollectionPageSize.',
            ).muted().small(),
          ),
        // Header
        _buildHeader(cs, shadcnCs),
        const Divider(height: 1),
        // Content
        material.Expanded(
          child: material.Padding(
            padding: const material.EdgeInsets.all(16),
            child: _effectiveType == 'string'
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
    final typeCol = _typeColor(_effectiveType);
    return material.Container(
      padding:
          const material.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: material.BoxDecoration(
        color: scs.muted.withValues(alpha: 0.15),
      ),
      child: material.Row(
        children: [
          material.Icon(_typeIcon(_effectiveType), size: 18, color: typeCol),
          const Gap(8),
          material.Container(
            padding:
                const material.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: material.BoxDecoration(
              color: typeCol.withValues(alpha: 0.12),
              borderRadius: material.BorderRadius.circular(4),
            ),
            child: Text(
              _effectiveType.toUpperCase(),
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
              _currentKeyName,
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
          if (!widget.isReadOnly) ...[
            material.Tooltip(
              message: 'Rename key',
              child: material.InkWell(
                onTap: _renameKey,
                borderRadius: material.BorderRadius.circular(4),
                child: material.Padding(
                  padding: const material.EdgeInsets.all(4),
                  child: material.Icon(
                    material.Icons.drive_file_rename_outline_rounded,
                    size: 16,
                    color: scs.mutedForeground,
                  ),
                ),
              ),
            ),
            const Gap(4),
          ],
          if (!widget.isReadOnly)
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
              onTap: () async {
                if (!await _confirmDiscardStringEdits()) return;
                await _load();
              },
              borderRadius: material.BorderRadius.circular(4),
              child: material.Padding(
                padding: const material.EdgeInsets.all(4),
                child: material.Icon(material.Icons.refresh_rounded,
                    size: 16, color: scs.mutedForeground),
              ),
            ),
          ),
          if (!widget.isReadOnly) ...[
            const Gap(4),
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
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, shadcn.ColorScheme scs) {
    switch (_effectiveType) {
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
        return _buildUnsupportedViewer();
    }
  }

  Widget _buildUnsupportedViewer() {
    final unknown = _effectiveType == 'unknown';
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        Text(unknown ? 'Type unknown' : 'Unsupported type').semiBold(),
        const Gap(8),
        Text(
          unknown
              ? 'This key is not opened as a string until TYPE succeeds. '
                  'GET and SET are disabled so the original type is not overwritten.'
              : '$_effectiveType keys cannot be opened with GET/SET. '
                  'Save is disabled so the original type is not replaced with a string.',
        ).muted().small(),
      ],
    );
  }

  // ─── String ─────────────────────────────────────────────────────────────

  Widget _buildStringEditor(ColorScheme cs, shadcn.ColorScheme scs) {
    if (_stringIsBinary) {
      final bulk = _stringValue!;
      return material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          Text('Binary value (${bulk.bytes.length} bytes)').semiBold(),
          const Gap(8),
          const Text(
            'Not valid UTF-8. Save as text is disabled so the original bytes are not overwritten.',
          ).muted().small(),
          const Gap(12),
          const Text('Hex').semiBold().small(),
          const Gap(4),
          material.SelectableText(
            bulk.toHex(),
            style: const material.TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
          const Gap(12),
          const Text('Base64').semiBold().small(),
          const Gap(4),
          material.SelectableText(
            bulk.toBase64(),
            style: const material.TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      );
    }
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('Value').semiBold(),
            if (!widget.isReadOnly) ...[
              const Spacer(),
              PrimaryButton(
                onPressed: _saveString,
                size: ButtonSize.small,
                leading:
                    const material.Icon(material.Icons.save_rounded, size: 14),
                child: const Text('Save'),
              ),
            ],
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
            readOnly: widget.isReadOnly,
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
        Text(_collectionHeading('Hash fields')).semiBold(),
        if (!widget.isReadOnly) ...[
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
        ],
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
                      field: entry.key.label,
                      value: entry.value.label,
                      onDelete:
                          widget.isReadOnly ? null : () => _hashDel(entry.key),
                      colorScheme: cs,
                      shadcnCs: scs,
                    );
                  },
                ),
        ),
        if (_hasMore) _loadMoreTile(),
      ],
    );
  }

  // ─── List ───────────────────────────────────────────────────────────────

  Widget _buildListEditor(ColorScheme cs, shadcn.ColorScheme scs) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        Text(_collectionHeading('List items')).semiBold(),
        if (!widget.isReadOnly) ...[
          const Gap(8),
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
        ],
        const Gap(12),
        material.Expanded(
          child: _listValue.isEmpty
              ? material.Center(child: const Text('No items').muted())
              : material.ListView.separated(
                  itemCount: _listValue.length,
                  separatorBuilder: (_, __) => const Gap(4),
                  itemBuilder: (context, i) => _IndexedValueRow(
                    index: i,
                    value: _listValue[i].label,
                    onEdit: widget.isReadOnly
                        ? null
                        : () async {
                            final edited = await showAppDialog<String>(
                              context: context,
                              builder: (ctx) => _RedisEditListDialogContent(
                                index: i,
                                initialValue: _listValue[i].label,
                              ),
                            );
                            if (edited != null &&
                                edited != _listValue[i].label) {
                              await _listSet(i, edited);
                            }
                          },
                    onDelete: widget.isReadOnly
                        ? null
                        : () => _listRemove(i, _listValue[i]),
                    colorScheme: cs,
                    shadcnCs: scs,
                  ),
                ),
        ),
        if (_hasMore) _loadMoreTile(),
      ],
    );
  }

  // ─── Set ────────────────────────────────────────────────────────────────

  Widget _buildSetEditor(ColorScheme cs, shadcn.ColorScheme scs) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        Text(_collectionHeading('Set members')).semiBold(),
        if (!widget.isReadOnly) ...[
          const Gap(8),
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
        ],
        const Gap(12),
        material.Expanded(
          child: _setValue.isEmpty
              ? material.Center(child: const Text('No members').muted())
              : material.ListView.separated(
                  itemCount: _setValue.length,
                  separatorBuilder: (_, __) => const Gap(4),
                  itemBuilder: (context, index) => _MemberRow(
                    member: _setValue[index].label,
                    onDelete: widget.isReadOnly
                        ? null
                        : () => _setRemove(_setValue[index]),
                    colorScheme: cs,
                    shadcnCs: scs,
                  ),
                ),
        ),
        if (_hasMore) _loadMoreTile(),
      ],
    );
  }

  // ─── Sorted Set ─────────────────────────────────────────────────────────

  Widget _buildZsetEditor(ColorScheme cs, shadcn.ColorScheme scs) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        Text(_collectionHeading('Sorted set')).semiBold(),
        if (!widget.isReadOnly) ...[
          const Gap(8),
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
        ],
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
                      member: member.label,
                      score: score,
                      onDelete:
                          widget.isReadOnly ? null : () => _zsetRemove(member),
                      colorScheme: cs,
                      shadcnCs: scs,
                    );
                  },
                ),
        ),
        if (_hasMore) _loadMoreTile(),
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
      case 'stream':
        return material.Icons.view_stream_rounded;
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

class _RedisRenameDialogContent extends material.StatefulWidget {
  const _RedisRenameDialogContent({
    required this.initialKey,
  });

  final String initialKey;

  @override
  material.State<_RedisRenameDialogContent> createState() =>
      _RedisRenameDialogContentState();
}

class _RedisRenameDialogContentState
    extends material.State<_RedisRenameDialogContent> {
  late final material.TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = material.TextEditingController(text: widget.initialKey);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    return AlertDialog(
      title: const Text('Rename Key'),
      content: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          const Text('Enter new key name').muted().small(),
          const Gap(8),
          TextField(
            controller: _controller,
            placeholder: const Text('New key name'),
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
            final val = _controller.text.trim();
            if (val.isNotEmpty) {
              Navigator.of(context).pop(val);
            }
          },
          child: const Text('Rename'),
        ),
      ],
    );
  }
}

class _RedisEditListDialogContent extends material.StatefulWidget {
  const _RedisEditListDialogContent({
    required this.index,
    required this.initialValue,
  });

  final int index;
  final String initialValue;

  @override
  material.State<_RedisEditListDialogContent> createState() =>
      _RedisEditListDialogContentState();
}

class _RedisEditListDialogContentState
    extends material.State<_RedisEditListDialogContent> {
  late final material.TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = material.TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    return AlertDialog(
      title: Text('Edit Item [${widget.index}]'),
      content: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          const Text('Enter new value').muted().small(),
          const Gap(8),
          TextField(
            controller: _controller,
            placeholder: const Text('Value'),
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
            Navigator.of(context).pop(_controller.text);
          },
          child: const Text('Save'),
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
    this.onDelete,
    required this.colorScheme,
    required this.shadcnCs,
  });

  final String field;
  final String value;
  final VoidCallback? onDelete;
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
          if (onDelete != null)
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
    this.onEdit,
    this.onDelete,
    required this.colorScheme,
    required this.shadcnCs,
  });

  final int index;
  final String value;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
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
          if (onEdit != null) ...[
            const Gap(8),
            material.Tooltip(
              message: 'Edit item',
              child: material.InkWell(
                onTap: onEdit,
                borderRadius: material.BorderRadius.circular(4),
                child: material.Padding(
                  padding: const material.EdgeInsets.all(4),
                  child: material.Icon(material.Icons.edit_outlined,
                      size: 14, color: shadcnCs.mutedForeground),
                ),
              ),
            ),
          ],
          if (onDelete != null) ...[
            const Gap(8),
            material.Tooltip(
              message: 'Delete item',
              child: material.InkWell(
                onTap: onDelete,
                borderRadius: material.BorderRadius.circular(4),
                child: material.Padding(
                  padding: const material.EdgeInsets.all(4),
                  child: material.Icon(material.Icons.close_rounded,
                      size: 14, color: context.semanticPalette.destructive),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    this.onDelete,
    required this.colorScheme,
    required this.shadcnCs,
  });

  final String member;
  final VoidCallback? onDelete;
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
          if (onDelete != null)
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
    this.onDelete,
    required this.colorScheme,
    required this.shadcnCs,
  });

  final String member;
  final double score;
  final VoidCallback? onDelete;
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
          if (onDelete != null)
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
