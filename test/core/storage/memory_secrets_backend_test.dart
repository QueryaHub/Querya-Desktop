import 'package:flutter_test/flutter_test.dart';

import '../../memory_secrets_backend.dart';

/// The fault injection of the test backend itself. The tests of the app's
/// handling of a failing keyring (`secrets_failure_test.dart`) lean on these
/// guarantees.
void main() {
  late MemorySecretsStorageBackend backend;

  setUp(() => backend = MemorySecretsStorageBackend());

  test('without faults it stores, reads and deletes, and counts the calls',
      () async {
    await backend.write('a', '1');
    expect(await backend.read('a'), '1');
    await backend.write('a', null);
    expect(await backend.read('a'), isNull);
    await backend.write('b', '2');
    await backend.delete('b');

    expect(backend.keys, isEmpty);
    expect(backend.writeCalls, 3);
    expect(backend.readCalls, 2);
    expect(backend.deleteCalls, 1);
  });

  test('failOnCall fires on the Nth call of that kind only, once', () async {
    backend.failOnCall(SecretsOp.write, 2, StateError('second'));

    await backend.write('a', '1');
    await expectLater(backend.write('b', '2'), throwsA(isA<StateError>()));
    await backend.write('c', '3');

    expect(backend.keys, {'a', 'c'});
    // Reads and deletes have their own numbering.
    expect(await backend.read('a'), '1');
    await backend.delete('a');
  });

  test('a failing call is counted and leaves the values untouched', () async {
    await backend.write('k', 'old');
    backend.failOnCall(SecretsOp.write, 2, StateError('write'));
    backend.failOnCall(SecretsOp.delete, 1, StateError('delete'));

    await expectLater(backend.write('k', 'new'), throwsA(isA<StateError>()));
    await expectLater(backend.delete('k'), throwsA(isA<StateError>()));

    expect(backend.writeCalls, 2);
    expect(backend.deleteCalls, 1);
    expect(await backend.read('k'), 'old');
  });

  test('failAlways keeps failing until heal; heal leaves values and counts',
      () async {
    await backend.write('k', 'v');
    backend.failAlways(SecretsOp.read, Exception('locked'));

    await expectLater(backend.read('k'), throwsException);
    await expectLater(backend.read('k'), throwsException);
    expect(backend.readCalls, 2);

    backend.heal(SecretsOp.read);
    expect(await backend.read('k'), 'v');
    expect(backend.readCalls, 3);
  });

  test('the failNext flags still fire once and win over the other faults',
      () async {
    backend.failNextRead = StateError('flag');
    backend.failOnCall(SecretsOp.read, 1, ArgumentError('scheduled'));
    backend.failAlways(SecretsOp.read, const FormatException('always'));

    await expectLater(backend.read('k'), throwsA(isA<StateError>()));
    expect(backend.failNextRead, isNull);
    await expectLater(backend.read('k'), throwsA(isA<FormatException>()));
  });

  test('resetCounts restarts the numbering and keeps values and faults',
      () async {
    await backend.write('k', 'v');
    await backend.write('k2', 'v2');
    backend.resetCounts();
    expect(backend.writeCalls, 0);

    backend.failOnCall(SecretsOp.write, 1, StateError('first after reset'));
    await expectLater(backend.write('k3', 'v3'), throwsA(isA<StateError>()));
    expect(backend.keys, {'k', 'k2'});
  });

  test('clear drops values, faults and counts', () async {
    await backend.write('k', 'v');
    backend.failNextWrite = StateError('x');
    backend.failOnCall(SecretsOp.read, 5, StateError('y'));
    backend.failAlways(SecretsOp.delete, StateError('z'));

    backend.clear();

    expect(backend.keys, isEmpty);
    expect(backend.writeCalls, 0);
    await backend.write('k', 'v');
    await backend.delete('k');
    for (var i = 0; i < 6; i++) {
      await backend.read('k');
    }
  });

  test('a call number below 1 is refused', () {
    expect(() => backend.failOnCall(SecretsOp.write, 0, StateError('x')),
        throwsArgumentError);
  });
}
