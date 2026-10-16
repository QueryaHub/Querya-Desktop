import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/harness/extension_manifest_validator.dart';
import 'package:querya_desktop/core/extensions/harness/extension_protocol_profile.dart';

Map<String, Object?> _valid() => {
      'id': 'acme.clickhouse',
      'name': 'ClickHouse',
      'version': '1.2.3',
      'type': 'database_driver',
      'main': 'bin/driver',
      'engines': {'querya_desktop': '^0.4.11'},
      'contributions': {
        'drivers': [
          {'driverId': 'clickhouse', 'displayName': 'ClickHouse'},
        ],
      },
    };

List<HarnessDiagnostic> _check(Object? manifest, [String target = '0.4.18']) =>
    validateExtensionManifest(
      manifest,
      ExtensionProtocolProfile.forTarget(target),
    );

void main() {
  test('a complete manifest has no diagnostics', () {
    expect(_check(_valid()), isEmpty);
  });

  test('non-object manifest is a single error', () {
    final d = _check([1, 2]);
    expect(d, hasLength(1));
    expect(d.single.isError, isTrue);
  });

  test('missing id and name name their paths', () {
    final m = _valid()..remove('id')..remove('name');
    final paths = _check(m).where((d) => d.isError).map((d) => d.path);
    expect(paths, containsAll(['id', 'name']));
  });

  test('wrong type and missing main are errors', () {
    final m = _valid()
      ..['type'] = 'theme'
      ..remove('main');
    final paths = _check(m).where((d) => d.isError).map((d) => d.path);
    expect(paths, containsAll(['type', 'main']));
  });

  test('bad version string is an error, missing one a warning', () {
    expect(
      _check(_valid()..['version'] = 'one'),
      contains(isA<HarnessDiagnostic>()
          .having((d) => d.path, 'path', 'version')
          .having((d) => d.isError, 'isError', isTrue)),
    );
    expect(
      _check(_valid()..remove('version')).single.isError,
      isFalse,
    );
  });

  test('driver contribution needs driverId and displayName', () {
    final m = _valid()
      ..['contributions'] = {
        'drivers': [
          {'driverId': 'x'},
        ],
      };
    final d = _check(m).single;
    expect(d.path, 'contributions.drivers[0].displayName');
  });

  test('no drivers at all is an error', () {
    final m = _valid()..['contributions'] = <String, Object?>{};
    expect(_check(m).single.path, 'contributions.drivers');
  });

  test('engine range excluding the target host is a warning', () {
    final d = _check(_valid()..['engines'] = {'querya_desktop': '^0.4.11'},
        '0.5.0');
    expect(d.single.path, 'engines.querya_desktop');
    expect(d.single.isError, isFalse);
  });

  test('>= ranges and unknown syntax are handled', () {
    expect(
        _check(_valid()..['engines'] = {'querya_desktop': '>=0.4.0'}, '0.5.0'),
        isEmpty);
    expect(
        _check(_valid()..['engines'] = {'querya_desktop': '~0.4'}).single.isError,
        isFalse);
  });

  test('commands on a host older than 0.4.16 warn', () {
    final m = _valid();
    (m['contributions']! as Map)['commands'] = [
      {'id': 'x'},
    ];
    final d = _check(m, '0.4.14');
    expect(d.single.path, 'contributions.commands');
    expect(_check(m, '0.4.16'), isEmpty);
  });

  group('manifestVersion', () {
    List<HarnessDiagnostic> errors(Object? manifest, [String target = '0.5.0']) =>
        _check(manifest, target).where((d) => d.isError).toList();

    test('absent means format 1 and is fine', () {
      expect(_check(_valid()), isEmpty);
    });

    test('format 1 is fine on every host that has the protocol', () {
      final m = _valid()..['manifestVersion'] = 1;
      for (final host in ['0.4.11', '0.4.18', '0.5.0']) {
        expect(_check(m, host), isEmpty, reason: host);
      }
    });

    test('a format newer than the host reads is an error naming the path', () {
      final d = errors(_valid()..['manifestVersion'] = 2);
      expect(d, hasLength(1));
      expect(d.single.path, 'manifestVersion');
      expect(d.single.message, contains('newer than Querya Desktop 0.5.0'));
    });

    test('a value that is not a whole number >= 1 is an error', () {
      for (final bad in [0, -1, 1.5, '1', true, <String>[]]) {
        final d = errors(_valid()..['manifestVersion'] = bad);
        expect(d.map((e) => e.path), ['manifestVersion'], reason: '$bad');
      }
    });
  });

  group('protocol profile manifest formats', () {
    test('every host with the protocol reads format 1', () {
      for (final host in ['0.4.11', '0.4.19', '0.5.0']) {
        expect(ExtensionProtocolProfile.forTarget(host).manifestVersion, 1);
      }
    });
  });
}
