import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/connection_pool_lock.dart';

void main() {
  test('two callers for one key share a single create()', () async {
    final lock = PoolEntryLock<int>();
    final gate = Completer<int>();
    var created = 0;
    Future<int> create() {
      created++;
      return gate.future;
    }

    final a = lock.createIfAbsent('k', create);
    final b = lock.createIfAbsent('k', create);
    gate.complete(7);

    expect(await a, 7);
    expect(await b, 7);
    expect(created, 1);
  });

  test('different keys are created in parallel', () async {
    final lock = PoolEntryLock<String>();
    final gates = {'a': Completer<String>(), 'b': Completer<String>()};
    final started = <String>[];

    final a = lock.createIfAbsent('a', () {
      started.add('a');
      return gates['a']!.future;
    });
    final b = lock.createIfAbsent('b', () {
      started.add('b');
      return gates['b']!.future;
    });
    await Future<void>.delayed(Duration.zero);

    // Both creations are running although neither has finished.
    expect(started, ['a', 'b']);
    gates['b']!.complete('B');
    gates['a']!.complete('A');
    expect(await a, 'A');
    expect(await b, 'B');
  });

  test('a finished creation is forgotten: the next call creates again', () async {
    final lock = PoolEntryLock<int>();
    var created = 0;
    Future<int> create() async => ++created;

    expect(await lock.createIfAbsent('k', create), 1);
    await Future<void>.delayed(Duration.zero);
    expect(await lock.createIfAbsent('k', create), 2);
  });

  test('a failing create() fails every waiter and clears the entry', () async {
    final lock = PoolEntryLock<int>();
    final gate = Completer<int>();
    var created = 0;

    final a = lock.createIfAbsent('k', () {
      created++;
      return gate.future;
    });
    final b = lock.createIfAbsent('k', () {
      created++;
      return gate.future;
    });
    final failures = [
      expectLater(a, throwsA(isA<StateError>())),
      expectLater(b, throwsA(isA<StateError>())),
    ];
    gate.completeError(StateError('connect refused'));
    await Future.wait(failures);
    expect(created, 1);

    await Future<void>.delayed(Duration.zero);
    expect(await lock.createIfAbsent('k', () async => 5), 5);
  });

  test('a create() that throws synchronously does not wedge the lock', () async {
    final lock = PoolEntryLock<int>();

    await expectLater(
      lock.createIfAbsent('k', () => throw StateError('boom')),
      throwsA(isA<StateError>()),
    );

    expect(await lock.createIfAbsent('k', () async => 1), 1);
    expect(await lock.createIfAbsent('other', () async => 2), 2);
  });
}
