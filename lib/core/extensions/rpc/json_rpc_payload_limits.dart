import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Default max UTF-8 byte length of one JSON-RPC stdout line (NDJSON).
///
/// Large `db.query` results are one object per line; without a bound the host
/// can OOM before Preferences row caps apply. Drivers should honor `limit`.
const int kDefaultJsonRpcMaxLineBytes = 32 * 1024 * 1024;

/// Lines above this UTF-8 length are `jsonDecode`d off the UI isolate.
const int kJsonRpcOffIsolateDecodeThresholdBytes = 64 * 1024;

/// Thrown when a plugin emits a newline-delimited JSON line larger than the
/// configured maximum.
class JsonRpcPayloadTooLargeException implements Exception {
  JsonRpcPayloadTooLargeException({
    required this.maxLineBytes,
    required this.receivedBytes,
  });

  final int maxLineBytes;
  final int receivedBytes;

  @override
  String toString() =>
      'JsonRpcPayloadTooLargeException: JSON-RPC line is $receivedBytes bytes '
      '(max $maxLineBytes). Reduce result size or pass a smaller `limit`.';
}

/// Splits a byte stream into UTF-8 lines, failing closed if any line exceeds
/// [maxLineBytes] (counted before decode).
StreamTransformer<List<int>, String> boundedUtf8LineSplitter({
  int maxLineBytes = kDefaultJsonRpcMaxLineBytes,
}) {
  return _BoundedUtf8LineSplitter(maxLineBytes: maxLineBytes);
}

class _BoundedUtf8LineSplitter
    extends StreamTransformerBase<List<int>, String> {
  _BoundedUtf8LineSplitter({required this.maxLineBytes});

  final int maxLineBytes;

  @override
  Stream<String> bind(Stream<List<int>> stream) {
    final controller = StreamController<String>(sync: true);
    final pending = BytesBuilder(copy: false);
    late final StreamSubscription<List<int>> sub;

    void fail(Object error, [StackTrace? st]) {
      if (!controller.isClosed) {
        controller.addError(error, st);
        controller.close();
      }
      sub.cancel();
    }

    void emitLine() {
      var bytes = pending.takeBytes();
      if (bytes.isNotEmpty && bytes.last == 0x0d) {
        bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
      }
      if (bytes.isEmpty) return;
      try {
        controller.add(utf8.decode(bytes));
      } catch (e, st) {
        fail(e, st);
      }
    }

    sub = stream.listen(
      (chunk) {
        for (var i = 0; i < chunk.length; i++) {
          final b = chunk[i];
          if (b == 0x0a) {
            emitLine();
            continue;
          }
          if (pending.length >= maxLineBytes) {
            fail(
              JsonRpcPayloadTooLargeException(
                maxLineBytes: maxLineBytes,
                receivedBytes: pending.length + 1,
              ),
            );
            return;
          }
          pending.addByte(b);
        }
      },
      onError: fail,
      onDone: () {
        if (pending.isNotEmpty) {
          if (pending.length > maxLineBytes) {
            fail(
              JsonRpcPayloadTooLargeException(
                maxLineBytes: maxLineBytes,
                receivedBytes: pending.length,
              ),
            );
            return;
          }
          emitLine();
        }
        controller.close();
      },
      cancelOnError: true,
    );

    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }
}
