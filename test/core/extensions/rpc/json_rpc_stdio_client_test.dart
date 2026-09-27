import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/rpc/json_rpc_payload_limits.dart';
import 'package:querya_desktop/core/extensions/rpc/json_rpc_stdio_client.dart';

void main() {
  group('boundedUtf8LineSplitter', () {
    test('splits lines and strips CR', () async {
      final lines = await Stream<List<int>>.fromIterable([
        utf8.encode('one\r\n'),
        utf8.encode('two\n'),
      ]).transform(boundedUtf8LineSplitter(maxLineBytes: 1024)).toList();
      expect(lines, ['one', 'two']);
    });

    test('fails closed when line exceeds max bytes', () async {
      final controller = StreamController<List<int>>();
      final errors = <Object>[];
      final sub = controller.stream
          .transform(boundedUtf8LineSplitter(maxLineBytes: 8))
          .listen((_) {}, onError: errors.add);

      controller.add(utf8.encode('123456789')); // 9 bytes, no newline yet
      await Future<void>.delayed(Duration.zero);
      expect(errors, isNotEmpty);
      expect(errors.first, isA<JsonRpcPayloadTooLargeException>());
      await sub.cancel();
      await controller.close();
    });
  });

  /// IOSink allows one flush at a time, so requests are issued one per turn.
  Future<List<Future<Object?>>> sendRequests(
    JsonRpcStdioClient client,
    int count,
  ) async {
    final replies = <Future<Object?>>[];
    for (var i = 1; i <= count; i++) {
      replies.add(client.sendRequest('q$i'));
      await Future<void>.delayed(Duration.zero);
    }
    return replies;
  }

  group('boundedUtf8LineSplitter backpressure', () {
    test('pausing the consumer pauses the byte source and resume resumes it',
        () async {
      var paused = 0;
      var resumed = 0;
      final source = StreamController<List<int>>(
        onPause: () => paused++,
        onResume: () => resumed++,
      );
      final lines = <String>[];
      final sub = source.stream
          .transform(boundedUtf8LineSplitter(maxLineBytes: 1024))
          .listen(lines.add);

      sub.pause();
      await Future<void>.delayed(Duration.zero);
      expect(paused, 1);
      expect(source.isPaused, isTrue);

      sub.resume();
      await Future<void>.delayed(Duration.zero);
      expect(resumed, 1);
      expect(source.isPaused, isFalse);

      source.add(utf8.encode('after\n'));
      await Future<void>.delayed(Duration.zero);
      expect(lines, ['after']);
      await sub.cancel();
      await source.close();
    });
  });

  group('JsonRpcStdioClient backpressure', () {
    // A reply bigger than kJsonRpcOffIsolateDecodeThresholdBytes is decoded in
    // an isolate, so handling is slower than arrival.
    String bigReply(int id) => jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': {'blob': 'x' * (kJsonRpcOffIsolateDecodeThresholdBytes + 1024)},
        });

    test('pauses stdout while a backlog is waiting and resumes after it drains',
        () async {
      const requests = 24;
      const limit = 4;
      final stdout = StreamController<List<int>>();
      final stdin = StreamController<List<int>>();
      final client = JsonRpcStdioClient(
        stdout: stdout.stream,
        stdin: IOSink(stdin.sink),
        maxBufferedLines: limit,
        requestTimeout: const Duration(seconds: 30),
      );
      stdin.stream.listen((_) {});

      final replies = await sendRequests(client, requests);

      var sawPaused = false;
      var peak = 0;
      final watcher = Timer.periodic(const Duration(milliseconds: 1), (_) {
        sawPaused = sawPaused || client.isReadPaused;
        peak = math.max(peak, client.bufferedLineCount);
      });

      for (var id = 1; id <= requests; id++) {
        stdout.add(utf8.encode('${bigReply(id)}\n'));
      }
      final results = await Future.wait(replies);
      watcher.cancel();

      expect(results, hasLength(requests));
      expect(sawPaused, isTrue, reason: 'stdout must be paused under backlog');
      // Lines already handed over when the pause lands may still arrive.
      expect(peak, lessThanOrEqualTo(limit + 2));
      expect(client.bufferedLineCount, 0);
      expect(client.isReadPaused, isFalse);
      expect(stdout.isPaused, isFalse);

      await client.close();
      await stdout.close();
      await stdin.close();
    });

    test('a fast producer cannot push the backlog past the limit', () async {
      const requests = 60;
      const limit = 3;
      var produced = 0;
      final start = Completer<void>();
      // An async* generator honours pause, like a real pipe would. It starts
      // only once every request is registered.
      Stream<List<int>> plugin() async* {
        await start.future;
        for (var id = 1; id <= requests; id++) {
          produced++;
          yield utf8.encode('${bigReply(id)}\n');
        }
      }

      final stdin = StreamController<List<int>>();
      stdin.stream.listen((_) {});
      final client = JsonRpcStdioClient(
        stdout: plugin(),
        stdin: IOSink(stdin.sink),
        maxBufferedLines: limit,
        requestTimeout: const Duration(seconds: 30),
      );

      // Register the requests the plugin answers; ids are assigned in order.
      final replies = await sendRequests(client, requests);
      start.complete();

      var peakAhead = 0;
      var handled = 0;
      for (final r in replies) {
        r.then((_) => handled++);
      }
      final watcher = Timer.periodic(const Duration(milliseconds: 1), (_) {
        peakAhead = math.max(peakAhead, produced - handled);
      });
      await Future.wait(replies);
      watcher.cancel();

      expect(produced, requests);
      // Produced-but-unhandled lines stay near the limit, not near 60.
      expect(peakAhead, lessThanOrEqualTo(limit + 6));

      await client.close();
      await stdin.close();
    });

    test('replies queued when stdout closes are still delivered', () async {
      final stdout = StreamController<List<int>>();
      final stdin = StreamController<List<int>>();
      stdin.stream.listen((_) {});
      final client = JsonRpcStdioClient(
        stdout: stdout.stream,
        stdin: IOSink(stdin.sink),
        requestTimeout: const Duration(seconds: 30),
      );
      final replies = await sendRequests(client, 3);

      // Large replies are decoded off-isolate, then the plugin exits at once.
      for (var id = 1; id <= 3; id++) {
        stdout.add(utf8.encode('${bigReply(id)}\n'));
      }
      await stdout.close();

      final results = await Future.wait(replies);
      expect(results, hasLength(3));
      expect((results.first as Map)['blob'], isA<String>());

      // Whatever is still unanswered after the close fails as before.
      await expectLater(
        client.sendRequest('late'),
        throwsA(isA<StateError>()),
      );
      await client.close();
      await stdin.close();
    });

    test('backlog is also bounded by bytes', () async {
      final stdout = StreamController<List<int>>();
      final stdin = StreamController<List<int>>();
      stdin.stream.listen((_) {});
      final client = JsonRpcStdioClient(
        stdout: stdout.stream,
        stdin: IOSink(stdin.sink),
        maxBufferedBytes: 1024,
        requestTimeout: const Duration(seconds: 30),
      );
      final replies = await sendRequests(client, 6);

      var sawPaused = false;
      final watcher = Timer.periodic(const Duration(milliseconds: 1), (_) {
        sawPaused = sawPaused || client.isReadPaused;
      });
      for (var id = 1; id <= 6; id++) {
        stdout.add(utf8.encode('${bigReply(id)}\n'));
      }
      await Future.wait(replies);
      watcher.cancel();
      expect(sawPaused, isTrue);

      await client.close();
      await stdout.close();
      await stdin.close();
    });
  });

  group('JsonRpcStdioClient payload bounds', () {
    test('completes pending request with payload-too-large error', () async {
      final stdout = StreamController<List<int>>();
      final stdin = StreamController<List<int>>();
      final client = JsonRpcStdioClient(
        stdout: stdout.stream,
        stdin: IOSink(stdin.sink),
        maxLineBytes: 32,
        requestTimeout: const Duration(seconds: 2),
      );

      final pending = client.sendRequest('db.query', {'sql': 'SELECT 1'});
      // Drain request line from fake stdin.
      await stdin.stream.first;

      // Oversized reply line (no newline until after overflow).
      stdout.add(List<int>.filled(40, 0x61)); // 'a' * 40
      await expectLater(pending, throwsA(isA<JsonRpcPayloadTooLargeException>()));

      await client.close();
      await stdout.close();
      await stdin.close();
    });

    test('decodes normal response', () async {
      final stdout = StreamController<List<int>>();
      final stdin = StreamController<List<int>>();
      final client = JsonRpcStdioClient(
        stdout: stdout.stream,
        stdin: IOSink(stdin.sink),
        requestTimeout: const Duration(seconds: 2),
      );

      final pending = client.sendRequest('ping');
      await stdin.stream.first;
      stdout.add(
        utf8.encode(
          '${jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'result': {'ok': true},
              })}\n',
        ),
      );
      final result = await pending;
      expect(result, isA<Map>());
      expect((result as Map)['ok'], true);

      await client.close();
      await stdout.close();
      await stdin.close();
    });
  });
}
