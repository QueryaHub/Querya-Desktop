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
  var truncated = false;
  await for (final item in stream) {
    if (items.length >= cap) {
      truncated = true;
      continue;
    }
    items.add(item);
    if (onProgress != null) {
      await onProgress(items.length);
    }
  }
  return (items: items, truncated: truncated);
}
