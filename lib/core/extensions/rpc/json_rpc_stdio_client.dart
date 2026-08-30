import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:querya_desktop/core/extensions/rpc/json_rpc_payload_limits.dart';

/// Minimal JSON-RPC 2.0 client over newline-delimited JSON on stdio.
///
/// Enough for Block E credential injection and later Block C methods without
/// pulling `json_rpc_2` yet. One JSON object per line on stdin/stdout.
///
/// Incoming lines are bounded by [maxLineBytes] (see
/// [kDefaultJsonRpcMaxLineBytes]); oversized payloads fail closed.
class JsonRpcStdioClient {
  JsonRpcStdioClient({
    required Stream<List<int>> stdout,
    required IOSink stdin,
    this.requestTimeout = const Duration(seconds: 10),
    this.maxLineBytes = kDefaultJsonRpcMaxLineBytes,
  })  : _stdin = stdin,
        _lines = stdout.transform(
          boundedUtf8LineSplitter(maxLineBytes: maxLineBytes),
        ) {
    _subscription = _lines.listen(
      _onLine,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  final IOSink _stdin;
  final Stream<String> _lines;
  final Duration requestTimeout;
  final int maxLineBytes;

  final Map<int, Completer<Object?>> _pending = {};
  var _nextId = 1;
  var _closed = false;
  StreamSubscription<String>? _subscription;
  Object? _fatalError;

  /// Number of RPC requests currently in-flight waiting for a response.
  int get pendingRequestCount => _pending.length;

  /// Returns true when there is at least one active RPC request in-flight.
  bool get hasPendingRequests => _pending.isNotEmpty;

  /// Serializes async line handling so large-line isolate decode stays ordered.
  Future<void> _lineChain = Future<void>.value();

  /// Sends a JSON-RPC request and waits for the matching response.
  Future<Object?> sendRequest(
    String method, [
    Object? params,
  ]) async {
    if (_closed) {
      throw StateError('JsonRpcStdioClient is closed');
    }
    if (_fatalError != null) {
      throw StateError('JsonRpcStdioClient failed: $_fatalError');
    }

    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;

    final payload = <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };

    _stdin.writeln(jsonEncode(payload));
    try {
      await _stdin.flush().timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _pending.remove(id);
      throw TimeoutException(
        'Failed to flush JSON-RPC request "$method" to plugin stdin within 3s',
      );
    } catch (e) {
      _pending.remove(id);
      rethrow;
    }

    try {
      return await completer.future.timeout(requestTimeout);
    } on TimeoutException {
      _pending.remove(id);
      throw TimeoutException(
        'JSON-RPC request "$method" timed out after $requestTimeout',
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    failAll(StateError('JsonRpcStdioClient closed'));
  }

  /// Completes all in-flight requests with [error] (e.g. plugin crash).
  void failAll(Object error, [StackTrace? stackTrace]) {
    _fatalError = error;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(error, stackTrace);
      }
    }
    _pending.clear();
  }

  void _onLine(String line) {
    _lineChain = _lineChain.then((_) => _handleLine(line));
  }

  Future<void> _handleLine(String line) async {
    if (line.trim().isEmpty) return;
    late final Map<String, dynamic> message;
    try {
      final Object decoded;
      if (line.length > kJsonRpcOffIsolateDecodeThresholdBytes) {
        decoded = await Isolate.run(() => jsonDecode(line));
      } else {
        decoded = jsonDecode(line);
      }
      if (decoded is! Map) return;
      message = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    final id = message['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;

    if (message.containsKey('error')) {
      final error = message['error'];
      completer.completeError(
        JsonRpcException.fromJson(error is Map ? error : {'message': '$error'}),
      );
      return;
    }
    completer.complete(message['result']);
  }

  void _onError(Object error, StackTrace stackTrace) {
    _fatalError = error;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(error, stackTrace);
      }
    }
    _pending.clear();
  }

  void _onDone() {
    _fatalError ??= StateError('Plugin stdout closed');
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(_fatalError!);
      }
    }
    _pending.clear();
  }
}

class JsonRpcException implements Exception {
  JsonRpcException({this.code, required this.message, this.data});

  factory JsonRpcException.fromJson(Map error) {
    return JsonRpcException(
      code: error['code'] is int ? error['code'] as int : null,
      message: '${error['message'] ?? 'JSON-RPC error'}',
      data: error['data'],
    );
  }

  final int? code;
  final String message;
  final Object? data;

  @override
  String toString() => 'JsonRpcException($code): $message';
}
