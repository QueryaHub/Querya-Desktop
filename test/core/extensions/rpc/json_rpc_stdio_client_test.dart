import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
