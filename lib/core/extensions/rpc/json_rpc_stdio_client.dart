import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimal JSON-RPC 2.0 client over newline-delimited JSON on stdio.
///
/// Enough for Block E credential injection and later Block C methods without
/// pulling `json_rpc_2` yet. One JSON object per line on stdin/stdout.
class JsonRpcStdioClient {
  JsonRpcStdioClient({
    required Stream<List<int>> stdout,
    required IOSink stdin,
    this.requestTimeout = const Duration(seconds: 10),
  })  : _stdin = stdin,
        _lines = utf8.decoder.bind(stdout).transform(const LineSplitter()) {
    _subscription = _lines.listen(_onLine, onError: _onError, onDone: _onDone);
  }

  final IOSink _stdin;
  final Stream<String> _lines;
  final Duration requestTimeout;

  final Map<int, Completer<Object?>> _pending = {};
  var _nextId = 1;
  var _closed = false;
  StreamSubscription<String>? _subscription;
  Object? _fatalError;

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
    await _stdin.flush();

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
    if (line.trim().isEmpty) return;
    late final Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return;
      message = decoded;
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
