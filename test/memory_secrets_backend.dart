import 'package:querya_desktop/core/storage/connection_secrets_store.dart';

/// Shared in-memory backend wired from `test/flutter_test_config.dart`.
final MemorySecretsStorageBackend testMemorySecrets =
    MemorySecretsStorageBackend();

/// The three backend operations a fault can be aimed at.
enum SecretsOp { read, write, delete }

/// In-memory secrets backend for `flutter test` (no OS keychain / libsecret).
///
/// Fault injection, all of it off by default:
///  * `failNextRead` / `failNextWrite` / `failNextDelete`: the next call of
///    that kind throws, then the flag clears.
///  * [failOnCall]: the Nth call of one kind throws, once.
///  * [failAlways]: every call of one kind throws until [heal].
///
/// A failing call throws before it touches the stored values, as a keyring
/// that refuses a request does. Calls are numbered per kind from 1, counting
/// every call that reaches the backend, failed ones included; [clear] and
/// [resetCounts] start the numbering over. When several faults apply to one
/// call, the `failNext*` flag wins, then [failOnCall], then [failAlways].
class MemorySecretsStorageBackend implements SecretsStorageBackend {
  final Map<String, String> _values = {};
  final Map<SecretsOp, int> _calls = {for (final op in SecretsOp.values) op: 0};
  final Map<SecretsOp, Map<int, Object>> _scheduled = {
    for (final op in SecretsOp.values) op: {},
  };
  final Map<SecretsOp, Object> _persistent = {};

  /// When non-null, the next [read] throws this error (then clears the flag).
  Object? failNextRead;

  /// When non-null, the next [write] throws this error (then clears the flag).
  Object? failNextWrite;

  /// When non-null, the next [delete] throws this error (then clears the flag).
  Object? failNextDelete;

  /// Calls of each kind since the last [clear] / [resetCounts], failed ones
  /// included.
  int get readCalls => _calls[SecretsOp.read]!;
  int get writeCalls => _calls[SecretsOp.write]!;
  int get deleteCalls => _calls[SecretsOp.delete]!;

  /// The keys that currently hold a value.
  Set<String> get keys => Set.unmodifiable(_values.keys);

  /// Makes call number [callNumber] (1-based, per kind, counted from the last
  /// reset) throw [error], once. A number that has already passed never fires.
  void failOnCall(SecretsOp op, int callNumber, Object error) {
    if (callNumber < 1) {
      throw ArgumentError.value(callNumber, 'callNumber', 'calls start at 1');
    }
    _scheduled[op]![callNumber] = error;
  }

  /// Makes every call of kind [op] throw [error] until [heal].
  void failAlways(SecretsOp op, Object error) => _persistent[op] = error;

  /// Drops every pending fault of kind [op] (the one-shot flag, scheduled
  /// calls and [failAlways]). Values and counters stay.
  void heal(SecretsOp op) {
    _scheduled[op]!.clear();
    _persistent.remove(op);
    switch (op) {
      case SecretsOp.read:
        failNextRead = null;
      case SecretsOp.write:
        failNextWrite = null;
      case SecretsOp.delete:
        failNextDelete = null;
    }
  }

  /// Starts the call numbering over. Faults and values stay.
  void resetCounts() {
    for (final op in SecretsOp.values) {
      _calls[op] = 0;
    }
  }

  /// Counts the call, and throws when a fault is aimed at it.
  void _enter(SecretsOp op) {
    final number = _calls[op] = _calls[op]! + 1;
    final Object? oneShot;
    switch (op) {
      case SecretsOp.read:
        oneShot = failNextRead;
        failNextRead = null;
      case SecretsOp.write:
        oneShot = failNextWrite;
        failNextWrite = null;
      case SecretsOp.delete:
        oneShot = failNextDelete;
        failNextDelete = null;
    }
    final fault = oneShot ?? _scheduled[op]!.remove(number) ?? _persistent[op];
    if (fault != null) throw fault;
  }

  @override
  Future<String?> read(String key) async {
    _enter(SecretsOp.read);
    return _values[key];
  }

  @override
  Future<void> write(String key, String? value) async {
    _enter(SecretsOp.write);
    if (value == null || value.isEmpty) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async {
    _enter(SecretsOp.delete);
    _values.remove(key);
  }

  /// Back to a fresh backend: no values, no faults, numbering from 1.
  void clear() {
    _values.clear();
    failNextRead = null;
    failNextWrite = null;
    failNextDelete = null;
    for (final op in SecretsOp.values) {
      _scheduled[op]!.clear();
    }
    _persistent.clear();
    resetCounts();
  }
}
