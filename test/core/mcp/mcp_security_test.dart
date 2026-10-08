import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/mcp/mcp_access_store.dart';
import 'package:querya_desktop/core/mcp/mcp_query_service.dart';
import 'package:querya_desktop/core/mcp/mcp_redaction.dart';
import 'package:querya_desktop/core/mcp/mcp_sql_delegates.dart';
import 'package:querya_desktop/core/mcp/mcp_sql_guard.dart';
import 'package:querya_desktop/core/mcp/querya_mcp_server.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/mysql/mysql_sql_workspace.dart';
import 'package:querya_desktop/features/postgresql/postgres_sql_workspace.dart';
import 'package:querya_desktop/features/sqlite/sqlite_sql_workspace.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';
import 'package:stream_channel/stream_channel.dart';

import '../../support/fake_sql_execution_delegate.dart';

/// #1138: the MCP server as an attacker would see it.

const _pw = 'Pg-Secret-9f2c';
const _sshPw = 'Ssh-Secret-41aa';
const _phrase = 'Key-Phrase-77de';
const _pem = '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAAB3NzaC1yc2EAAA\n'
    '-----END OPENSSH PRIVATE KEY-----';
const _secrets = [_pw, _sshPw, _phrase, 'AAAAB3NzaC1yc2EAAA', 'db.internal'];

class _Access implements McpAccessPolicy {
  _Access(this.ids);
  final Set<int> ids;
  @override
  Future<bool> canRead(ConnectionRow row) async => ids.contains(row.id);
}

ConnectionRow _row(int id, String type) => ConnectionRow(
      id: id,
      type: type,
      name: 'conn $id',
      host: type == 'sqlite' ? '/home/me/secret/shop.db' : 'db.internal',
      port: 5432,
      username: 'admin',
      password: _pw,
      databaseName: 'shop',
      connectionString: 'postgresql://admin:$_pw@db.internal:5432/shop',
      createdAt: DateTime.utc(2026).toIso8601String(),
      sshSecrets:
          SshTunnelSecrets(password: _sshPw, privateKey: _pem, passphrase: _phrase),
    );

SqlExecutionResult _catalog(String sql) {
  if (sql.contains('FOREIGN KEY') || sql.contains('foreign_key')) {
    return const SqlExecutionResult(columns: ['t', 'c', 'rt', 'rc']);
  }
  if (sql.contains('information_schema.columns') ||
      sql.contains('pragma_table_info')) {
    return const SqlExecutionResult(columns: ['t', 'c', 'ty', 'pk'], rows: [
      ['users', 'id', 'integer', '1'],
    ]);
  }
  return const SqlExecutionResult(columns: ['n'], rows: [
    ['1'],
  ]);
}

/// Client and server over an in-memory channel.
Future<(ServerConnection, QueryaMcpServer)> _connect(McpQueryService service) async {
  final pair = StreamChannelController<String>();
  final server = QueryaMcpServer(pair.local, service: service, version: 't');
  final client = MCPClient(Implementation(name: 'attacker', version: '1'));
  final conn = client.connectServer(pair.foreign);
  await conn.initialize(InitializeRequest(
    protocolVersion: ProtocolVersion.latestSupported,
    capabilities: ClientCapabilities(),
    clientInfo: Implementation(name: 'attacker', version: '1'),
  ));
  conn.notifyInitialized();
  return (conn, server);
}

String _text(CallToolResult r) =>
    r.content.map((c) => (c as TextContent).text).join('\n');

void main() {
  group('every write form is refused before the driver', () {
    final writes = <(String, SqlDialect)>[
      for (final sql in [
        'INSERT INTO t VALUES (1)',
        'insert into t select * from u',
        'UPDATE t SET a = 1',
        'DELETE FROM t',
        'MERGE INTO t USING s ON (t.id = s.id) WHEN MATCHED THEN DELETE',
        'TRUNCATE t',
        'DROP TABLE t',
        'DROP DATABASE shop',
        'CREATE TABLE t (id int)',
        'CREATE INDEX i ON t (a)',
        'ALTER TABLE t ADD COLUMN b int',
        'GRANT SELECT ON t TO bob',
        'REVOKE ALL ON t FROM bob',
        'COMMENT ON TABLE t IS \'x\'',
        'LOCK TABLE t',
        'REINDEX TABLE t',
        'CLUSTER t',
        'VACUUM FULL',
        'ANALYZE t',
        'REFRESH MATERIALIZED VIEW mv',
        'COPY t FROM \'/etc/passwd\'',
        'CALL p()',
        'DO \$\$ BEGIN DELETE FROM t; END \$\$',
        'PREPARE q AS DELETE FROM t',
        'EXECUTE q',
        'SET default_transaction_read_only = off',
        'SET SESSION CHARACTERISTICS AS TRANSACTION READ WRITE',
        'RESET ALL',
        'BEGIN READ WRITE',
        'START TRANSACTION READ WRITE',
        'COMMIT',
        'NOTIFY ch',
        'LISTEN ch',
        'SELECT 1; DELETE FROM t',
        'SELECT 1;\nDROP TABLE t;',
        'WITH x AS (DELETE FROM t RETURNING *) SELECT * FROM x',
        'WITH x AS (INSERT INTO t VALUES (1) RETURNING *) SELECT 1',
        'EXPLAIN ANALYZE DELETE FROM t',
        'EXPLAIN (ANALYZE true) SELECT 1',
        'SELECT * INTO new_t FROM t',
        'SELECT * FROM t FOR UPDATE',
        'SELECT pg_terminate_backend(1)',
        "SELECT set_config('default_transaction_read_only','off',false)",
        "SELECT * FROM dblink('host=x', 'DELETE FROM t') AS r(a int)",
        "SELECT lo_export(1, '/tmp/x')",
        'DE/**/LETE FROM t',
      ])
        (sql, SqlDialect.postgres),
      for (final sql in [
        'REPLACE INTO t VALUES (1)',
        'LOAD DATA INFILE \'/etc/passwd\' INTO TABLE t',
        "SELECT * FROM t INTO OUTFILE '/tmp/t.csv'",
        'SELECT 1 /*! ; DROP TABLE t */',
        '/*!50000 DROP TABLE t */',
        'SELECT 1 /*M! , SLEEP(10) */',
        'HANDLER t OPEN',
        'FLUSH PRIVILEGES',
        'KILL 42',
        'SHUTDOWN',
        'INSTALL PLUGIN x SONAME \'x.so\'',
        'OPTIMIZE TABLE t',
        'RENAME TABLE t TO u',
        "SELECT LOAD_FILE('/etc/passwd')",
        'SELECT * FROM t LOCK IN SHARE MODE',
      ])
        (sql, SqlDialect.mysql),
      for (final sql in [
        "ATTACH DATABASE '/tmp/x.db' AS x",
        'DETACH DATABASE x',
        'PRAGMA query_only = 0',
        'PRAGMA writable_schema = 1',
        'PRAGMA journal_mode = DELETE',
        'REINDEX',
        "SELECT load_extension('/tmp/evil.so')",
        "SELECT writefile('/tmp/x', 'y')",
      ])
        (sql, SqlDialect.sqlite),
    ];

    for (final (sql, dialect) in writes) {
      test('${dialect.name}: ${sql.replaceAll('\n', ' ')}', () {
        expect(McpSqlGuard.check(sql, dialect), isNotNull);
      });
    }

    test('none of them reaches the delegate through run_query / explain_query',
        () async {
      final types = {
        SqlDialect.postgres: 'postgresql',
        SqlDialect.mysql: 'mysql',
        SqlDialect.sqlite: 'sqlite',
      };
      final db = FakeSqlExecutionDelegate()..onExecute = _catalog;
      final rows = [
        for (final e in types.entries) _row(e.key.index + 1, e.value),
      ];
      final service = McpQueryService(
        createDelegate: (row, dialect) => db,
        access: _Access({1, 2, 3}),
        loadConnections: () async => rows,
      );
      for (final (sql, dialect) in writes) {
        final id = dialect.index + 1;
        await expectLater(service.runQuery(id, sql),
            throwsA(isA<McpToolException>()), reason: sql);
        await expectLater(service.explainQuery(id, sql),
            throwsA(isA<McpToolException>()), reason: sql);
      }
      expect(db.executed, isEmpty);
      expect(db.explained, isEmpty);
    });
  });

  test('the production delegates always open read-only sessions', () {
    final pg = createReadOnlyMcpDelegate(_row(1, 'postgresql'), SqlDialect.postgres);
    final my = createReadOnlyMcpDelegate(_row(2, 'mysql'), SqlDialect.mysql);
    final lite = createReadOnlyMcpDelegate(_row(3, 'sqlite'), SqlDialect.sqlite);
    expect((pg as PostgresSqlExecutionDelegate).isReadOnly, isTrue);
    expect((my as MysqlSqlExecutionDelegate).isReadOnly, isTrue);
    expect((lite as SqliteSqlExecutionDelegate).isReadOnly, isTrue);
    for (final d in [pg, my, lite]) {
      d.dispose();
    }
  });

  group('no secret leaves through any tool', () {
    late FakeSqlExecutionDelegate db;
    late ServerConnection conn;
    late QueryaMcpServer server;

    setUp(() async {
      db = FakeSqlExecutionDelegate()..onExecute = _catalog;
      (conn, server) = await _connect(McpQueryService(
        createDelegate: (row, dialect) => db,
        access: _Access({1, 3}),
        loadConnections: () async => [_row(1, 'postgresql'), _row(3, 'sqlite')],
      ));
    });
    tearDown(() => server.shutdown());

    Future<String> callAll() async {
      final out = StringBuffer();
      Future<void> call(String tool, Map<String, Object?> args) async =>
          out.writeln(_text(await conn.callTool(
              CallToolRequest(name: tool, arguments: args))));
      for (final id in [1, 3]) {
        await call('list_connections', {});
        await call('list_tables', {'connection_id': id});
        await call('describe_table', {'connection_id': id, 'table': 'users'});
        await call('sample_rows', {'connection_id': id, 'table': 'users'});
        await call('run_query', {'connection_id': id, 'sql': 'SELECT 1'});
        await call('explain_query', {'connection_id': id, 'sql': 'SELECT 1'});
        try {
          final r = await conn.readResource(ReadResourceRequest(uri: 'schema://$id'));
          out.writeln(jsonEncode(r.contents));
        } catch (e) {
          out.writeln('$e');
        }
      }
      return out.toString();
    }

    test('in normal results', () async {
      final all = await callAll();
      expect(all, contains('users'));
      for (final s in [..._secrets, 'admin', '/home/me/secret']) {
        expect(all, isNot(contains(s)), reason: s);
      }
    });

    test('in driver errors that quote the connection', () async {
      const leak = 'connection to postgresql://admin:$_pw@db.internal:5432/shop '
          'failed: password=$_pw sslkey passphrase=$_phrase ssh pw $_sshPw\n$_pem';
      db.onExecute = (_) => throw StateError(leak);
      db.explainError = StateError(leak);
      final all = await callAll();
      for (final s in [_pw, _sshPw, _phrase, 'AAAAB3NzaC1yc2EAAA', 'admin:']) {
        expect(all, isNot(contains(s)), reason: s);
      }
    });

    test('when creating the delegate fails', () async {
      await server.shutdown();
      (conn, server) = await _connect(McpQueryService(
        createDelegate: (row, dialect) =>
            throw StateError('keyring: password=$_pw for ${row.connectionString}'),
        access: _Access({1}),
        loadConnections: () async => [_row(1, 'postgresql')],
      ));
      final r = await conn.callTool(CallToolRequest(
          name: 'run_query', arguments: {'connection_id': 1, 'sql': 'SELECT 1'}));
      expect(r.isError, isTrue);
      expect(_text(r), isNot(contains(_pw)));
    });
  });

  test('a connection that is not shared is invisible to every tool', () async {
    var created = 0;
    final (conn, server) = await _connect(McpQueryService(
      createDelegate: (row, dialect) {
        created++;
        return FakeSqlExecutionDelegate()..onExecute = _catalog;
      },
      access: _Access({}),
      loadConnections: () async => [_row(1, 'postgresql')],
    ));
    addTearDown(server.shutdown);

    final list = await conn.callTool(
        CallToolRequest(name: 'list_connections', arguments: {}));
    expect(jsonDecode(_text(list)), isEmpty);

    for (final (tool, args) in [
      ('list_tables', {'connection_id': 1}),
      ('describe_table', {'connection_id': 1, 'table': 'users'}),
      ('sample_rows', {'connection_id': 1, 'table': 'users'}),
      ('run_query', {'connection_id': 1, 'sql': 'SELECT 1'}),
      ('explain_query', {'connection_id': 1, 'sql': 'SELECT 1'}),
    ]) {
      final r = await conn.callTool(CallToolRequest(name: tool, arguments: args));
      expect(r.isError, isTrue, reason: tool);
      expect(_text(r), contains('not available'), reason: tool);
    }
    await expectLater(
        conn.readResource(ReadResourceRequest(uri: 'schema://1')),
        throwsA(anything));
    expect(created, 0);
  });

  group('McpRedaction', () {
    test('masks URI user info, key=value secrets and PEM keys', () {
      final out = McpRedaction.redact(
        'mysql://root:hunter22@h/db and mongodb+srv://u:p@c.net '
        'password="a b" pwd=xyz token: abc123\n$_pem',
      );
      expect(out, isNot(contains('hunter22')));
      expect(out, isNot(contains('u:p@')));
      expect(out, isNot(contains('"a b"')));
      expect(out, isNot(contains('xyz')));
      expect(out, isNot(contains('abc123')));
      expect(out, isNot(contains('AAAAB3NzaC1yc2EAAA')));
      expect(out, contains('mysql://***@h/db'));
    });

    test('leaves ordinary text alone', () {
      const text = 'relation "users" does not exist at character 15';
      expect(McpRedaction.redact(text), text);
    });
  });
}
