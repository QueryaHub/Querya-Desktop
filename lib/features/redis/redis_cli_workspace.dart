import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/workspace/destructive_query_dialog.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Known Redis commands for auto-completion.
const List<String> kRedisCommands = [
  'APPEND', 'AUTH', 'BGREWRITEAOF', 'BGSAVE', 'BITCOUNT', 'BITFIELD', 'BITOP', 'BITPOS',
  'BLMOVE', 'BLPOP', 'BRPOP', 'BZPOPMIN', 'BZPOPMAX',
  'CLIENT', 'COMMAND', 'CONFIG', 'DBSIZE', 'DECR', 'DECRBY', 'DEL', 'DISCARD', 'DUMP',
  'ECHO', 'EVAL', 'EVALSHA', 'EXEC', 'EXISTS', 'EXPIRE', 'EXPIREAT',
  'FLUSHALL', 'FLUSHDB', 'FUNCTION',
  'GET', 'GETBIT', 'GETDEL', 'GETRANGE', 'GETSET',
  'HDEL', 'HEXISTS', 'HGET', 'HGETALL', 'HINCRBY', 'HINCRBYFLOAT', 'HKEYS', 'HLEN',
  'HMGET', 'HMSET', 'HRANDFIELD', 'HSCAN', 'HSET', 'HSETNX', 'HSTRLEN', 'HVALS',
  'INCR', 'INCRBY', 'INCRBYFLOAT', 'INFO',
  'KEYS', 'LASTSAVE', 'LINDEX', 'LINSERT', 'LLEN', 'LMOVE', 'LPOP', 'LPOS', 'LPUSH',
  'LPUSHX', 'LRANGE', 'LREM', 'LSET', 'LTRIM',
  'MEMORY', 'MGET', 'MONITOR', 'MSET', 'MSETNX', 'MULTI',
  'OBJECT', 'PERSIST', 'PEXPIRE', 'PEXPIREAT', 'PFADD', 'PFCOUNT', 'PFMERGE',
  'PING', 'PSETEX', 'PSUBSCRIBE', 'PTTL', 'PUBLISH', 'PUBSUB', 'PUNSUBSCRIBE',
  'QUIT', 'RANDOMKEY', 'READONLY', 'READWRITE', 'RENAME', 'RENAMENX', 'RESTORE', 'ROLE',
  'RPOP', 'RPOPLPUSH', 'RPUSH', 'RPUSHX',
  'SADD', 'SAVE', 'SCAN', 'SCARD', 'SCRIPT', 'SDIFF', 'SDIFFSTORE', 'SELECT',
  'SET', 'SETBIT', 'SETEX', 'SETNX', 'SETRANGE', 'SHUTDOWN', 'SINTER', 'SINTERCARD',
  'SINTERSTORE', 'SISMEMBER', 'SLOWLOG', 'SMEMBERS', 'SMISMEMBER', 'SMOVE', 'SPOP',
  'SRANDMEMBER', 'SREM', 'SSCAN', 'STRLEN', 'SUBSCRIBE', 'SUNION', 'SUNIONSTORE',
  'TIME', 'TOUCH', 'TTL', 'TYPE', 'UNSUBSCRIBE', 'UNWATCH', 'WAIT', 'WATCH',
  'XACK', 'XADD', 'XAUTOCLAIM', 'XCLAIM', 'XDEL', 'XGROUP', 'XINFO', 'XLEN',
  'XPENDING', 'XRANGE', 'XREAD', 'XREADGROUP', 'XREVRANGE', 'XTRIM',
  'ZADD', 'ZCARD', 'ZCOUNT', 'ZDIFF', 'ZINCRBY', 'ZINTER', 'ZLEXCOUNT', 'ZMSCORE',
  'ZPOPMAX', 'ZPOPMIN', 'ZRANDMEMBER', 'ZRANGE', 'ZRANGEBYLEX', 'ZRANGEBYSCORE',
  'ZRANK', 'ZREM', 'ZREMRANGEBYLEX', 'ZREMRANGEBYRANK', 'ZREMRANGEBYSCORE',
  'ZREVRANGE', 'ZREVRANGEBYLEX', 'ZREVRANGEBYSCORE', 'ZREVRANK', 'ZSCAN', 'ZSCORE',
];

/// Splits command line into arguments while respecting quotes and escapes.
List<String> parseRedisCliCommand(String input) {
  final args = <String>[];
  final buffer = StringBuffer();
  var inDoubleQuote = false;
  var inSingleQuote = false;
  var escaped = false;

  for (var i = 0; i < input.length; i++) {
    final char = input[i];

    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }

    if (char == r'\') {
      escaped = true;
      continue;
    }

    if (char == '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
      continue;
    }

    if (char == "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
      continue;
    }

    if (char.trim().isEmpty && !inDoubleQuote && !inSingleQuote) {
      if (buffer.isNotEmpty) {
        args.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }

    buffer.write(char);
  }

  if (buffer.isNotEmpty) {
    args.add(buffer.toString());
  }

  return args;
}

/// Dangerous Redis commands that require confirmation.
class RedisCliDangerousCommand {
  final DestructiveSqlType type;
  final String targetName;
  final String message;

  const RedisCliDangerousCommand({
    required this.type,
    required this.targetName,
    required this.message,
  });
}

/// Inspects command arguments for destructive or dangerous operations.
RedisCliDangerousCommand? checkDangerousRedisCommand(
    List<String> args, int currentDb) {
  if (args.isEmpty) return null;
  final cmd = args.first.toUpperCase();

  if (cmd == 'FLUSHALL') {
    return const RedisCliDangerousCommand(
      type: DestructiveSqlType.redisFlushAll,
      targetName: 'all databases',
      message: 'FLUSHALL will delete every key across all databases!',
    );
  }
  if (cmd == 'FLUSHDB') {
    return RedisCliDangerousCommand(
      type: DestructiveSqlType.redisFlushDb,
      targetName: 'db$currentDb',
      message:
          'FLUSHDB will delete all keys in the current database (db$currentDb)!',
    );
  }
  if (cmd == 'SHUTDOWN') {
    return const RedisCliDangerousCommand(
      type: DestructiveSqlType.redisShutdown,
      targetName: 'server',
      message: 'SHUTDOWN will terminate the Redis server process!',
    );
  }
  if (cmd == 'KEYS') {
    final pattern = args.length > 1 ? args[1] : '*';
    if (pattern.contains('*') || pattern.contains('?')) {
      return RedisCliDangerousCommand(
        type: DestructiveSqlType.redisKeys,
        targetName: pattern,
        message:
            'Running "KEYS $pattern" can block Redis on large databases. Use SCAN instead.',
      );
    }
  }
  return null;
}

/// Formatted Redis CLI execution result.
class RedisCliEntry {
  final String command;
  final int database;
  final String output;
  final bool isError;
  final int? latencyMs;
  final DateTime timestamp;

  const RedisCliEntry({
    required this.command,
    required this.database,
    required this.output,
    this.isError = false,
    this.latencyMs,
    required this.timestamp,
  });
}

/// Formats any Redis reply into a standard RESP string representation.
String formatRespReply(Object? reply) {
  if (reply == null) return '(nil)';
  if (reply is int) return '(integer) $reply';
  if (reply is bool) return reply ? '(integer) 1' : '(integer) 0';
  if (reply is RedisBulkValue) {
    return reply.isUtf8 ? '"${reply.text}"' : reply.label;
  }
  if (reply is Uint8List) {
    try {
      final decoded = utf8.decode(reply);
      return '"$decoded"';
    } catch (_) {
      final bulk = RedisBulkValue.fromReply(reply);
      return bulk.label;
    }
  }
  if (reply is List) {
    if (reply.isEmpty) return '(empty array)';
    final buf = StringBuffer();
    _formatRespArray(reply, '', buf);
    return buf.toString().trimRight();
  }
  final s = reply.toString();
  if (s == 'OK' || s == 'PONG') return s;
  return '"$s"';
}

void _formatRespArray(List items, String indent, StringBuffer buf) {
  for (var i = 0; i < items.length; i++) {
    final numPrefix = '$indent${i + 1}) ';
    final item = items[i];
    if (item is List) {
      if (item.isEmpty) {
        buf.writeln('$numPrefix(empty array)');
      } else {
        buf.writeln(numPrefix);
        final nextIndent = '   $indent';
        _formatRespArray(item, nextIndent, buf);
      }
    } else {
      buf.writeln('$numPrefix${formatRespReply(item)}');
    }
  }
}

/// Interactive Redis CLI Terminal Console workspace.
class RedisCliWorkspace extends material.StatefulWidget {
  const RedisCliWorkspace({
    super.key,
    required this.connectionRow,
    required this.connection,
    this.database = 0,
    this.onBack,
  });

  final ConnectionRow connectionRow;
  final RedisConnection connection;
  final int database;
  final material.VoidCallback? onBack;

  @override
  material.State<RedisCliWorkspace> createState() => _RedisCliWorkspaceState();
}

class _RedisCliWorkspaceState extends material.State<RedisCliWorkspace> {
  final List<RedisCliEntry> _entries = [];
  final List<String> _history = [];
  int _historyIndex = -1;
  String _draftCommand = '';

  late int _currentDb;
  bool _executing = false;

  final material.TextEditingController _inputController =
      material.TextEditingController();
  final material.FocusNode _inputFocusNode = material.FocusNode();
  final material.ScrollController _scrollController =
      material.ScrollController();

  List<String> _suggestions = [];

  String get _historyStorageKey =>
      'redis_cli_history_${widget.connectionRow.id ?? widget.connection.id}';

  @override
  void initState() {
    super.initState();
    _currentDb = widget.database;
    unawaited(_loadHistory());
    _addInitialBanner();
  }

  void _addInitialBanner() {
    _entries.add(
      RedisCliEntry(
        command: 'INFO',
        database: _currentDb,
        output:
            'Connected to Redis at ${widget.connection.host}:${widget.connection.port} (db$_currentDb).\n'
            'Type any Redis command (e.g. GET, HGETALL, INFO, PING). Tab for autocomplete. Type "clear" to clear.',
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> _loadHistory() async {
    try {
      final raw = await LocalDb.instance.getAppSetting(_historyStorageKey);
      if (raw != null && raw.isNotEmpty && mounted) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          setState(() {
            _history.clear();
            _history.addAll(decoded.map((e) => e.toString()));
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final capped = _history.length > 200
          ? _history.sublist(_history.length - 200)
          : _history;
      await LocalDb.instance.setAppSetting(
        _historyStorageKey,
        jsonEncode(capped),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: material.Curves.easeOut,
        );
      }
    });
  }

  void _handleHistoryNavigation(bool isUp) {
    if (_history.isEmpty) return;

    if (isUp) {
      if (_historyIndex == -1) {
        _draftCommand = _inputController.text;
      }
      if (_historyIndex < _history.length - 1) {
        setState(() {
          _historyIndex++;
          final cmd = _history[_history.length - 1 - _historyIndex];
          _inputController.text = cmd;
          _inputController.selection = material.TextSelection.collapsed(
            offset: cmd.length,
          );
        });
      }
    } else {
      if (_historyIndex > 0) {
        setState(() {
          _historyIndex--;
          final cmd = _history[_history.length - 1 - _historyIndex];
          _inputController.text = cmd;
          _inputController.selection = material.TextSelection.collapsed(
            offset: cmd.length,
          );
        });
      } else if (_historyIndex == 0) {
        setState(() {
          _historyIndex = -1;
          _inputController.text = _draftCommand;
          _inputController.selection = material.TextSelection.collapsed(
            offset: _draftCommand.length,
          );
        });
      }
    }
  }

  void _handleTabCompletion() {
    final text = _inputController.text;
    if (text.isEmpty) return;

    final tokens = parseRedisCliCommand(text);
    if (tokens.isEmpty) return;

    final firstToken = tokens.first.toUpperCase();
    final matches = kRedisCommands
        .where((cmd) => cmd.startsWith(firstToken))
        .toList();

    if (matches.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    if (matches.length == 1) {
      final completed = matches.first;
      final remainder = text.substring(tokens.first.length);
      final newText = '$completed$remainder ';
      setState(() {
        _inputController.text = newText;
        _inputController.selection = material.TextSelection.collapsed(
          offset: newText.length,
        );
        _suggestions = [];
      });
    } else {
      setState(() {
        _suggestions = matches.take(15).toList();
      });
    }
  }

  Future<void> _submitCommand() async {
    final rawText = _inputController.text.trim();
    if (rawText.isEmpty || _executing) return;

    setState(() {
      _suggestions = [];
      _historyIndex = -1;
      _draftCommand = '';
    });

    _inputController.clear();

    // Check special client commands
    final lower = rawText.toLowerCase();
    if (lower == 'clear') {
      setState(() {
        _entries.clear();
      });
      return;
    }
    if (lower == 'help') {
      setState(() {
        _entries.add(
          RedisCliEntry(
            command: rawText,
            database: _currentDb,
            output:
                'Querya Redis CLI Console\n'
                'Supported: any RESP command (GET, SET, HGETALL, XADD, EVAL, etc.)\n'
                'Navigation: Up/Down for command history\n'
                'Autocomplete: Tab to complete command names\n'
                'Commands: "clear" (clear screen), "help" (this help)',
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
      return;
    }

    // Record history
    if (_history.isEmpty || _history.last != rawText) {
      _history.add(rawText);
      unawaited(_saveHistory());
    }

    final args = parseRedisCliCommand(rawText);
    if (args.isEmpty) return;

    // Dangerous command check
    final dangerous = checkDangerousRedisCommand(args, _currentDb);
    if (dangerous != null) {
      final confirmed = await confirmDestructiveAction(
        context: context,
        type: dangerous.type,
        targetName: dangerous.targetName,
        commandPreview: rawText,
        connectionName: widget.connection.name,
      );
      if (!confirmed) {
        setState(() {
          _entries.add(
            RedisCliEntry(
              command: rawText,
              database: _currentDb,
              output: '(cancelled: operation aborted by user)',
              timestamp: DateTime.now(),
            ),
          );
        });
        _scrollToBottom();
        return;
      }
    }

    setState(() => _executing = true);

    final stopwatch = Stopwatch()..start();
    try {
      // Connect if needed
      if (!widget.connection.isConnected) {
        await widget.connection.connect();
      }

      // SELECT tracking
      if (args.first.toUpperCase() == 'SELECT' && args.length > 1) {
        final targetDb = int.tryParse(args[1]);
        if (targetDb != null) {
          await widget.connection.selectDatabase(targetDb);
          stopwatch.stop();
          if (mounted) {
            setState(() {
              _currentDb = targetDb;
              _entries.add(
                RedisCliEntry(
                  command: rawText,
                  database: _currentDb,
                  output: 'OK',
                  latencyMs: stopwatch.elapsedMilliseconds,
                  timestamp: DateTime.now(),
                ),
              );
              _executing = false;
            });
            _scrollToBottom();
          }
          return;
        }
      }

      final reply = await widget.connection.sendCommand(args);
      stopwatch.stop();

      final formatted = formatRespReply(reply);
      if (mounted) {
        setState(() {
          _entries.add(
            RedisCliEntry(
              command: rawText,
              database: _currentDb,
              output: formatted,
              latencyMs: stopwatch.elapsedMilliseconds,
              timestamp: DateTime.now(),
            ),
          );
          _executing = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        final errText = e.toString().replaceFirst('Exception: ', '');
        setState(() {
          _entries.add(
            RedisCliEntry(
              command: rawText,
              database: _currentDb,
              output: '(error) $errText',
              isError: true,
              latencyMs: stopwatch.elapsedMilliseconds,
              timestamp: DateTime.now(),
            ),
          );
          _executing = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _applySuggestion(String commandName) {
    final text = _inputController.text;
    final tokens = parseRedisCliCommand(text);
    final remainder = tokens.isNotEmpty
        ? text.substring(tokens.first.length).trimLeft()
        : '';
    final newText = remainder.isEmpty ? '$commandName ' : '$commandName $remainder';
    setState(() {
      _inputController.text = newText;
      _inputController.selection = material.TextSelection.collapsed(
        offset: newText.length,
      );
      _suggestions = [];
    });
    _inputFocusNode.requestFocus();
  }

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showAppToast(
        context: context,
        message: '$label copied to clipboard',
        variant: AppToastVariant.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return material.Container(
      color: cs.card,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          // Header Toolbar
          material.Container(
            height: 40,
            padding: const material.EdgeInsets.symmetric(horizontal: 16),
            decoration: material.BoxDecoration(
              color: cs.muted.withValues(alpha: 0.15),
              border: material.Border(
                bottom: material.BorderSide(
                  color: cs.border.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                material.Icon(
                  material.Icons.terminal_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                const Gap(8),
                const Text('Redis CLI Console').semiBold().small(),
                const Gap(8),
                material.Container(
                  padding: const material.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: material.BoxDecoration(
                    color: cs.muted.withValues(alpha: 0.25),
                    borderRadius: material.BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${widget.connection.host}:${widget.connection.port} [db$_currentDb]',
                    style: material.TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: cs.mutedForeground,
                    ),
                  ),
                ),
                const Spacer(),
                OutlineButton(
                  onPressed: () {
                    setState(() {
                      _entries.clear();
                    });
                  },
                  size: ButtonSize.small,
                  leading: const material.Icon(
                    material.Icons.cleaning_services_rounded,
                    size: 13,
                  ),
                  child: const Text('Clear'),
                ),
                if (widget.onBack != null) ...[
                  const Gap(8),
                  OutlineButton(
                    onPressed: widget.onBack,
                    size: ButtonSize.small,
                    leading: const material.Icon(
                      material.Icons.close_rounded,
                      size: 14,
                    ),
                    child: const Text('Close CLI'),
                  ),
                ],
              ],
            ),
          ),
          // Output Area
          material.Expanded(
            child: material.ListView.builder(
              controller: _scrollController,
              padding: const material.EdgeInsets.all(12),
              itemCount: _entries.length,
              itemBuilder: (context, i) {
                return _buildEntryItem(_entries[i], cs);
              },
            ),
          ),
          // Suggestion Chips (Tab Autocomplete)
          if (_suggestions.isNotEmpty)
            material.Container(
              height: 34,
              padding: const material.EdgeInsets.symmetric(horizontal: 12),
              decoration: material.BoxDecoration(
                color: cs.muted.withValues(alpha: 0.2),
                border: material.Border(
                  top: material.BorderSide(
                    color: cs.border.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: material.ListView.separated(
                scrollDirection: material.Axis.horizontal,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const Gap(6),
                itemBuilder: (context, i) {
                  final suggestion = _suggestions[i];
                  return material.Center(
                    child: material.InkWell(
                      onTap: () => _applySuggestion(suggestion),
                      borderRadius: material.BorderRadius.circular(4),
                      child: material.Container(
                        padding: const material.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: material.BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.15),
                          borderRadius: material.BorderRadius.circular(4),
                          border: material.Border.all(
                            color: cs.primary.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          suggestion,
                          style: material.TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: material.FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          // Command Input Bar
          material.Container(
            padding: const material.EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: material.BoxDecoration(
              color: cs.muted.withValues(alpha: 0.1),
              border: material.Border(
                top: material.BorderSide(
                  color: cs.border.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'db$_currentDb >',
                  style: material.TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: material.FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
                const Gap(8),
                material.Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          _handleHistoryNavigation(true);
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          _handleHistoryNavigation(false);
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.tab) {
                          _handleTabCompletion();
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocusNode,
                      autofocus: true,
                      placeholder: const Text('Enter Redis command (Tab to autocomplete)...'),
                      onSubmitted: (_) => _submitCommand(),
                    ),
                  ),
                ),
                const Gap(8),
                PrimaryButton(
                  onPressed: _executing ? null : _submitCommand,
                  size: ButtonSize.small,
                  leading: _executing
                      ? const material.SizedBox(
                          width: 14,
                          height: 14,
                          child: material.CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const material.Icon(
                          material.Icons.play_arrow_rounded,
                          size: 16,
                        ),
                  child: const Text('Run'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryItem(RedisCliEntry entry, ColorScheme cs) {
    return material.Container(
      margin: const material.EdgeInsets.only(bottom: 10),
      padding: const material.EdgeInsets.all(8),
      decoration: material.BoxDecoration(
        color: cs.muted.withValues(alpha: 0.08),
        borderRadius: material.BorderRadius.circular(6),
        border: material.Border.all(
          color: cs.border.withValues(alpha: 0.2),
        ),
      ),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          // Command Line Prompt Header
          Row(
            children: [
              Text(
                'db${entry.database} > ',
                style: material.TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: material.FontWeight.w600,
                  color: cs.primary,
                ),
              ),
              material.Expanded(
                child: Text(
                  entry.command,
                  style: const material.TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: material.FontWeight.w600,
                  ),
                ),
              ),
              if (entry.latencyMs != null) ...[
                const Gap(8),
                material.Container(
                  padding: const material.EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: material.BoxDecoration(
                    color: cs.muted.withValues(alpha: 0.2),
                    borderRadius: material.BorderRadius.circular(3),
                  ),
                  child: Text(
                    '${entry.latencyMs} ms',
                    style: material.TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: cs.mutedForeground,
                    ),
                  ),
                ),
              ],
              const Gap(8),
              material.InkWell(
                onTap: () => _copyText(entry.output, 'Output'),
                borderRadius: material.BorderRadius.circular(4),
                child: material.Padding(
                  padding: const material.EdgeInsets.all(2),
                  child: material.Icon(
                    material.Icons.copy_rounded,
                    size: 13,
                    color: cs.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
          const Gap(6),
          // Output Text
          material.SelectableText(
            entry.output,
            style: material.TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: entry.isError
                  ? cs.destructive
                  : (entry.output.startsWith('(nil)')
                      ? const Color(0xFFF97316) // Amber
                      : cs.foreground),
            ),
          ),
        ],
      ),
    );
  }
}
