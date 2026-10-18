/// Keeps the first [cap] events from [stream], then drains the rest.
///
/// Cancelling a MySQL `rowsStream` at the cap leaves COM_QUERY unread
/// (`waitingCommandResponse`); the next execute waits for
/// `connectionEstablished` and can time out. Draining lets the producer
/// finish (EOF) so the session returns to ready.
Future<({List<T> items, bool truncated})> takeThenDrain<T>(
  Stream<T> stream,
  int cap, {
  Future<void> Function(int count)? onProgress,
}) async {
  final items = <T>[];
  final r = await forEachThenDrain<T>(
    stream,
    cap,
    onItem: items.add,
    onProgress: onProgress,
  );
  return (items: items, truncated: r.truncated);
}

/// [takeThenDrain] for a caller that consumes each of the first [cap] events
/// as it arrives (packing it into columns) and has no use for the list.
Future<({int count, bool truncated})> forEachThenDrain<T>(
  Stream<T> stream,
  int cap, {
  required void Function(T item) onItem,
  Future<void> Function(int count)? onProgress,
}) async {
  var count = 0;
  var truncated = false;
  await for (final item in stream) {
    if (count >= cap) {
      truncated = true;
      continue;
    }
    onItem(item);
    count++;
    if (onProgress != null) {
      await onProgress(count);
    }
  }
  return (count: count, truncated: truncated);
}
