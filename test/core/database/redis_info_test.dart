import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_info.dart';

/// Sample Redis INFO output (trimmed to a few sections).
const _sampleInfo = '''
# Server
redis_version:7.2.4
redis_mode:standalone
os:Linux 6.5.0
tcp_port:6379
uptime_in_days:12

# Clients
connected_clients:5
maxclients:10000

# Memory
used_memory:1048576
used_memory_human:1.00M
used_memory_rss_human:2.50M
used_memory_peak_human:3.00M
mem_fragmentation_ratio:2.38

# Stats
instantaneous_ops_per_sec:42
total_commands_processed:123456
keyspace_hits:9000
keyspace_misses:1000

# CPU
used_cpu_sys_main_thread:1.23
used_cpu_user_main_thread:4.56

# Errorstats
errorstat_ERR:count=7

# Keyspace
db0:keys=100,expires=10,avg_ttl=5000

# Replication
role:master
''';

void main() {
  group('parseRedisInfo', () {
    late RedisInfoSections info;

    setUp(() {
      info = parseRedisInfo(_sampleInfo);
    });

    test('parses all sections', () {
      expect(info.keys, containsAll([
        'Server',
        'Clients',
        'Memory',
        'Stats',
        'CPU',
        'Errorstats',
        'Keyspace',
        'Replication',
      ]));
    });

    test('parses key:value pairs correctly', () {
      expect(info['Server']?['redis_version'], '7.2.4');
      expect(info['Server']?['redis_mode'], 'standalone');
      expect(info['Server']?['tcp_port'], '6379');
      expect(info['Server']?['uptime_in_days'], '12');
    });

    test('parses Clients section', () {
      expect(info['Clients']?['connected_clients'], '5');
      expect(info['Clients']?['maxclients'], '10000');
    });

    test('parses Memory section', () {
      expect(info['Memory']?['used_memory'], '1048576');
      expect(info['Memory']?['used_memory_human'], '1.00M');
      expect(info['Memory']?['mem_fragmentation_ratio'], '2.38');
    });

    test('parses Stats section', () {
      expect(info['Stats']?['instantaneous_ops_per_sec'], '42');
      expect(info['Stats']?['total_commands_processed'], '123456');
      expect(info['Stats']?['keyspace_hits'], '9000');
      expect(info['Stats']?['keyspace_misses'], '1000');
    });

    test('parses CPU section', () {
      expect(info['CPU']?['used_cpu_sys_main_thread'], '1.23');
      expect(info['CPU']?['used_cpu_user_main_thread'], '4.56');
    });

    test('handles Errorstats (colon-delimited, value contains =)', () {
      // errorstat_ERR:count=7 — parser splits on first colon:
      // key = 'errorstat_ERR', value = 'count=7'
      expect(info['Errorstats']?['errorstat_ERR'], 'count=7');
    });

    test('parses Keyspace db entries', () {
      expect(info['Keyspace']?['db0'], 'keys=100,expires=10,avg_ttl=5000');
    });

    test('parses Replication section', () {
      expect(info['Replication']?['role'], 'master');
    });

    test('returns empty map for empty input', () {
      final empty = parseRedisInfo('');
      expect(empty, isEmpty);
    });

    test('handles input with only blank lines', () {
      final blank = parseRedisInfo('\n\n\n');
      expect(blank, isEmpty);
    });

    test('handles section header without any keys', () {
      final result = parseRedisInfo('# EmptySection\n\n# Another\nkey:val');
      expect(result.containsKey('EmptySection'), true);
      expect(result['EmptySection'], isEmpty);
      expect(result['Another']?['key'], 'val');
    });

    test('ignores lines before any section header', () {
      final result = parseRedisInfo('orphan_key:orphan_val\n# S\nk:v');
      expect(result['S']?['k'], 'v');
      // orphan_key should not appear anywhere since no section was active
      expect(result.values.expand((m) => m.keys).contains('orphan_key'), false);
    });
  });

  group('sectionValue', () {
    test('returns value when key exists', () {
      final info = parseRedisInfo(_sampleInfo);
      expect(sectionValue(info, 'Server', 'redis_version'), '7.2.4');
    });

    test('returns null for missing key', () {
      final info = parseRedisInfo(_sampleInfo);
      expect(sectionValue(info, 'Server', 'nonexistent'), isNull);
    });

    test('returns null for missing section', () {
      final info = parseRedisInfo(_sampleInfo);
      expect(sectionValue(info, 'NoSuchSection', 'key'), isNull);
    });
  });

  group('sectionInt', () {
    test('parses integer value', () {
      final info = parseRedisInfo(_sampleInfo);
      expect(sectionInt(info, 'Clients', 'connected_clients'), 5);
      expect(sectionInt(info, 'Stats', 'keyspace_hits'), 9000);
    });

    test('returns null for non-integer value', () {
      final info = parseRedisInfo(_sampleInfo);
      expect(sectionInt(info, 'Memory', 'used_memory_human'), isNull);
    });

    test('returns null for missing key', () {
      final info = parseRedisInfo(_sampleInfo);
      expect(sectionInt(info, 'Server', 'missing'), isNull);
    });
  });

  group('sectionDouble', () {
    test('parses double value', () {
      final info = parseRedisInfo(_sampleInfo);
      expect(sectionDouble(info, 'Memory', 'mem_fragmentation_ratio'), 2.38);
      expect(sectionDouble(info, 'CPU', 'used_cpu_sys_main_thread'), 1.23);
    });

    test('parses integer as double', () {
      final info = parseRedisInfo(_sampleInfo);
      expect(sectionDouble(info, 'Stats', 'keyspace_hits'), 9000.0);
    });

    test('returns null for non-numeric value', () {
      final info = parseRedisInfo(_sampleInfo);
      expect(sectionDouble(info, 'Server', 'redis_mode'), isNull);
    });

    test('returns null for missing key', () {
      final info = parseRedisInfo(_sampleInfo);
      expect(sectionDouble(info, 'Server', 'nope'), isNull);
    });
  });
}
