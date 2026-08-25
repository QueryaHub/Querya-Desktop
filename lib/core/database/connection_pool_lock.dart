import 'dart:async';

/// Serializes the synchronous check-and-set for creating a pool entry per key.
///
/// Multiple callers waiting for the same key all receive the same creation
/// [Future], so only one underlying connection is produced. Different keys can
/// still be created concurrently because the lock is only held while the map
/// of pending futures is inspected/updated.
class PoolEntryLock<T> {
  final Map<String, Future<T>> _pending = {};
  Future<void>? _lock;

  /// Returns a [Future] that resolves to the created value for [key].
  /// If a creation for [key] is already in progress, the existing future is
  /// returned. Otherwise, [create] is started and its future is stored.
  Future<T> createIfAbsent(String key, Future<T> Function() create) async {
    // Wait for any other caller that is currently updating the pending map.
    while (_lock != null) {
      await _lock;
    }
    final completer = Completer<void>();
    _lock = completer.future;
    Future<T> result;
    try {
      final existing = _pending[key];
      if (existing != null) {
        result = existing;
      } else {
        final future = create();
        _pending[key] = future;
        // Ensure the pending entry is removed once the creation finishes, and
        // swallow errors on the cleanup chain so they don't become unhandled.
        final guarded = future.whenComplete(() => _pending.remove(key));
        guarded.then((_) {}, onError: (_) {});
        result = future;
      }
    } finally {
      completer.complete();
      if (_lock == completer.future) {
        _lock = null;
      }
    }
    return result;
  }
}
