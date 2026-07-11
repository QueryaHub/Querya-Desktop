import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/extensions/sandbox/embedded/declarative_embedded_engine.dart';
import 'package:querya_desktop/core/extensions/sandbox/embedded/embedded_sandbox_engine.dart';
import 'package:querya_desktop/core/extensions/sandbox/embedded/embedded_sandbox_runtime.dart';
import 'package:querya_desktop/core/extensions/sandbox/embedded/native_embedded_engines.dart';

void main() {
  group('DeclarativeEmbeddedEngine', () {
    late DeclarativeEmbeddedEngine engine;

    setUp(() {
      engine = DeclarativeEmbeddedEngine();
    });

    test('transforms SDUI documents with rename/defaults/drop', () async {
      const source = '''
{
  "kind": "sdui.transform",
  // rename title → heading
  "renameKeys": { "title": "heading" },
  "defaults": { "version": 1 },
  "dropKeys": ["debug"]
}
''';
      final result = await engine.invoke(
        const EmbeddedInvokeRequest(
          method: EmbeddedInvokeMethod.sduiTransform,
          source: source,
          args: {
            'document': {
              'title': 'Hello',
              'debug': true,
              'body': 'x',
            },
          },
        ),
      );

      expect(result.ok, isTrue);
      final doc = result.value! as Map<String, Object?>;
      expect(doc['heading'], 'Hello');
      expect(doc['version'], 1);
      expect(doc.containsKey('title'), isFalse);
      expect(doc.containsKey('debug'), isFalse);
    });

    test('formats SQL and uppercases keywords', () async {
      final result = await engine.invoke(
        const EmbeddedInvokeRequest(
          method: EmbeddedInvokeMethod.sqlFormat,
          source: '{"kind":"sql.format"}',
          args: {'sql': 'select  *  from users where id=1;'},
        ),
      );
      expect(result.ok, isTrue);
      expect(result.value, 'SELECT * FROM users WHERE id=1;\n');
    });

    test('generates hints filtered by prefix', () async {
      const source = '''
{
  "kind": "hints.generate",
  "tables": [
    { "name": "users", "columns": ["id", "email"] },
    { "name": "orders", "columns": ["id"] }
  ]
}
''';
      final result = await engine.invoke(
        const EmbeddedInvokeRequest(
          method: EmbeddedInvokeMethod.hintsGenerate,
          source: source,
          args: {'prefix': 'us'},
        ),
      );
      expect(result.ok, isTrue);
      final hints = (result.value! as List).cast<Map>();
      expect(hints.any((h) => h['label'] == 'users'), isTrue);
      expect(hints.any((h) => h['label'] == 'orders'), isFalse);
    });

    test('parses SQL statement kind', () async {
      final result = await engine.invoke(
        const EmbeddedInvokeRequest(
          method: EmbeddedInvokeMethod.sqlParse,
          source: '{"kind":"sql.parse","dialect":"postgresql"}',
          args: {'sql': '  update users set x=1 '},
        ),
      );
      expect(result.ok, isTrue);
      final ast = result.value! as Map;
      expect(ast['statement'], 'UPDATE');
      expect(ast['dialect'], 'postgresql');
    });
  });

  group('EmbeddedSandboxRuntime', () {
    test('falls back to declarative when QuickJS FFI is unavailable', () async {
      final runtime = EmbeddedSandboxRuntime(
        quickJs: QuickJsEmbeddedEngine(),
      );
      final result = await runtime.invoke(
        request: const EmbeddedInvokeRequest(
          method: EmbeddedInvokeMethod.sqlFormat,
          source: '{"kind":"sql.format"}',
          args: {'sql': 'select 1'},
        ),
        engineOverride: SandboxEngine.quickjs,
      );
      expect(result.ok, isTrue);
      expect(result.value, contains('SELECT'));
    });

    test('rejects embedded invoke when network permission is requested', () async {
      final runtime = EmbeddedSandboxRuntime();
      final manifest = ExtensionManifest(
        id: 'bad.script',
        name: 'Bad',
        version: '1.0.0',
        publisher: 'Test',
        type: ExtensionType.script,
        engines: const {'querya_desktop': '*'},
        sandbox: SandboxCapabilities.fromJson(const {
          'engine': 'quickjs',
          'permissions': {
            'network': {'mode': 'connection_host_only'},
          },
        }),
      );

      final result = await runtime.invoke(
        request: const EmbeddedInvokeRequest(
          method: EmbeddedInvokeMethod.sqlFormat,
          source: '{"kind":"sql.format"}',
          args: {'sql': 'select 1'},
        ),
        manifest: manifest,
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('Sandbox policy'));
    });

    test('rejects process engine on embedded runtime', () async {
      final runtime = EmbeddedSandboxRuntime();
      final result = await runtime.invoke(
        request: const EmbeddedInvokeRequest(
          method: EmbeddedInvokeMethod.invoke,
          source: '{}',
        ),
        engineOverride: SandboxEngine.process,
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('OS-process'));
    });
  });

  group('Native embedded engines', () {
    test('report unavailable and throw on invoke', () async {
      final qjs = QuickJsEmbeddedEngine();
      final wasm = WasmEmbeddedEngine();
      expect(qjs.isAvailable, isFalse);
      expect(wasm.isAvailable, isFalse);
      await expectLater(
        qjs.invoke(const EmbeddedInvokeRequest(
          method: EmbeddedInvokeMethod.invoke,
        )),
        throwsA(isA<EmbeddedEngineUnavailableException>()),
      );
    });
  });
}
