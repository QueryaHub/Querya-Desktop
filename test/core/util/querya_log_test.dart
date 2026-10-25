import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/util/log_ignored.dart';
import 'package:querya_desktop/core/util/querya_log.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('querya_log_test_');
  });
  tearDown(() => root.delete(recursive: true));

  Future<String> read(String name) =>
      File(p.join(root.path, name)).readAsString();

  test('writes timestamped lines with level and area', () async {
    final log = QueryaLog();
    await log.init(root);
    log.warn('storage', 'could not save', error: StateError('disk full'));
    await log.flush();

    final text = await read(QueryaLog.fileName);
    expect(text, matches(RegExp(r'^\d{4}-\d\d-\d\dT[\d:.]+Z WARN  \[storage\] could not save')));
    expect(text, contains('disk full'));
  });

  test('lines logged before init are kept and written on init', () async {
    final log = QueryaLog();
    log.info('app', 'start');
    await log.init(root);
    await log.flush();

    expect(await read(QueryaLog.fileName), contains('[app] start'));
  });

  test('rotates by size and keeps at most maxFiles', () async {
    final log = QueryaLog(maxBytes: 200, maxFiles: 3);
    await log.init(root);
    for (var i = 0; i < 40; i++) {
      log.info('t', 'line number $i ${'x' * 20}');
    }
    await log.flush();

    final files = root.listSync().whereType<File>().map((f) => p.basename(f.path)).toSet();
    expect(files, {'querya.log', 'querya.1.log', 'querya.2.log'});
    expect(await read(QueryaLog.fileName), contains('line number 39'));
    expect(await read('querya.1.log'), isNot(contains('line number 0 ')));
    for (final name in files) {
      expect(File(p.join(root.path, name)).lengthSync(), lessThanOrEqualTo(200));
    }
    final tail = await log.tail(3);
    expect(tail.last, contains('line number 39'));
  });

  test('passwords and URL user info are redacted', () async {
    final log = QueryaLog();
    await log.init(root);
    log.error(
      'conn',
      'connect failed for postgresql://admin:hunter22@db/shop password=hunter22',
      error: 'mysql://root:s3cret@h/x',
    );
    await log.flush();

    final text = await read(QueryaLog.fileName);
    expect(text, isNot(contains('hunter22')));
    expect(text, isNot(contains('s3cret')));
    expect(text, contains('[conn]'));
  });

  test('a multi-line stack stays inside one entry', () async {
    final log = QueryaLog();
    await log.init(root);
    log.error('x', 'boom', stack: StackTrace.fromString('#0 a\n#1 b'));
    await log.flush();

    final lines = (await read(QueryaLog.fileName)).trimRight().split('\n');
    expect(lines.first, contains('boom'));
    expect(lines.skip(1), everyElement(startsWith('    ')));
  });

  test('a directory that cannot be used never makes logging throw', () async {
    final blocker = File(p.join(root.path, 'a_file'))..writeAsStringSync('x');
    final log = QueryaLog();

    await log.init(Directory(p.join(blocker.path, 'logs')));
    log.error('x', 'still fine');
    await log.flush();

    expect(log.directory, isNull);
    expect(await log.tail(), isEmpty);
  });

  test('a file that fails to write is skipped, later lines still go out', () async {
    final log = QueryaLog();
    await log.init(root);
    // A directory where the log file belongs makes the append fail.
    await Directory(p.join(root.path, QueryaLog.fileName)).create();
    log.info('x', 'lost');
    await log.flush();
    await Directory(p.join(root.path, QueryaLog.fileName)).delete();
    log.info('x', 'kept');
    await log.flush();

    expect(await read(QueryaLog.fileName), contains('kept'));
  });

  test('logIgnored writes to the shared log', () async {
    await QueryaLog.instance.init(root);
    logIgnored('Somewhere.close', StateError('already closed'));
    await QueryaLog.instance.flush();

    final text = await read(QueryaLog.fileName);
    expect(text, contains('[Somewhere.close] ignored'));
    expect(text, contains('already closed'));
  });
}
