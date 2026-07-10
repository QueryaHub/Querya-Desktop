import 'dart:convert';

import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/extensions/sandbox/embedded/embedded_sandbox_engine.dart';

/// Pure-Dart Level-1 engine for JSON / JSONC declarative modules.
///
/// Guests declare transforms in data form — no eval, no network, no filesystem.
/// Suitable for SDUI transformers, SQL formatters, and hint generators until
/// QuickJS / WASM FFI backends are linked.
class DeclarativeEmbeddedEngine implements EmbeddedSandboxEngine {
  @override
  SandboxEngine get engine => SandboxEngine.quickjs; // logical Level-1 slot

  /// Alternate id when the module explicitly targets wasm-shaped JSON modules.
  final bool treatAsWasm;

  DeclarativeEmbeddedEngine({this.treatAsWasm = false});

  @override
  bool get isAvailable => true;

  @override
  Future<void> dispose() async {}

  @override
  Future<EmbeddedInvokeResult> invoke(EmbeddedInvokeRequest request) async {
    final source = request.source;
    if (source == null || source.trim().isEmpty) {
      return EmbeddedInvokeResult.failure('Module source is empty.');
    }

    late final Map<String, dynamic> module;
    try {
      module = _parseJsoncObject(source);
    } catch (e) {
      return EmbeddedInvokeResult.failure('Invalid declarative module: $e');
    }

    final kind = module['kind'] as String? ?? 'pipeline';
    switch (request.method) {
      case EmbeddedInvokeMethod.sduiTransform:
        return _sduiTransform(module, request.args);
      case EmbeddedInvokeMethod.sqlFormat:
        return _sqlFormat(module, request.args);
      case EmbeddedInvokeMethod.hintsGenerate:
        return _hintsGenerate(module, request.args);
      case EmbeddedInvokeMethod.sqlParse:
        return _sqlParse(module, request.args);
      case EmbeddedInvokeMethod.invoke:
        return _dispatchByKind(kind, module, request);
    }
  }

  EmbeddedInvokeResult _dispatchByKind(
    String kind,
    Map<String, dynamic> module,
    EmbeddedInvokeRequest request,
  ) {
    switch (kind) {
      case 'sdui.transform':
      case 'sdui':
        return _sduiTransform(module, request.args);
      case 'sql.format':
      case 'sql_format':
        return _sqlFormat(module, request.args);
      case 'hints.generate':
      case 'hints':
        return _hintsGenerate(module, request.args);
      case 'sql.parse':
      case 'sql_parse':
        return _sqlParse(module, request.args);
      default:
        return EmbeddedInvokeResult.failure('Unknown module kind "$kind".');
    }
  }

  EmbeddedInvokeResult _sduiTransform(
    Map<String, dynamic> module,
    Map<String, Object?> args,
  ) {
    final input = args['document'];
    if (input is! Map) {
      return EmbeddedInvokeResult.failure(
        'sdui.transform requires args.document as a JSON object.',
      );
    }
    final doc = Map<String, Object?>.from(
      input.map((k, v) => MapEntry('$k', v)),
    );

    final renames = module['renameKeys'];
    if (renames is Map) {
      for (final entry in renames.entries) {
        final from = '${entry.key}';
        final to = '${entry.value}';
        if (doc.containsKey(from)) {
          doc[to] = doc.remove(from);
        }
      }
    }

    final defaults = module['defaults'];
    if (defaults is Map) {
      for (final entry in defaults.entries) {
        doc.putIfAbsent('${entry.key}', () => entry.value);
      }
    }

    final drop = module['dropKeys'];
    if (drop is List) {
      for (final key in drop) {
        doc.remove('$key');
      }
    }

    return EmbeddedInvokeResult.success(doc);
  }

  EmbeddedInvokeResult _sqlFormat(
    Map<String, dynamic> module,
    Map<String, Object?> args,
  ) {
    final sql = args['sql'];
    if (sql is! String) {
      return EmbeddedInvokeResult.failure('sql.format requires args.sql string.');
    }

    var out = sql.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    out = out.replaceAll(RegExp(r'\s*;\s*'), ';\n');
    final upperKeywords = module['uppercaseKeywords'] != false;
    if (upperKeywords) {
      const keywords = [
        'select',
        'from',
        'where',
        'and',
        'or',
        'join',
        'left',
        'right',
        'inner',
        'outer',
        'on',
        'group',
        'by',
        'order',
        'limit',
        'insert',
        'into',
        'values',
        'update',
        'set',
        'delete',
      ];
      for (final kw in keywords) {
        out = out.replaceAllMapped(
          RegExp('\\b$kw\\b', caseSensitive: false),
          (m) => kw.toUpperCase(),
        );
      }
    }
    return EmbeddedInvokeResult.success(out);
  }

  EmbeddedInvokeResult _hintsGenerate(
    Map<String, dynamic> module,
    Map<String, Object?> args,
  ) {
    final tables = module['tables'];
    if (tables is! List) {
      return EmbeddedInvokeResult.failure(
        'hints.generate module requires "tables" array.',
      );
    }
    final prefix = (args['prefix'] as String? ?? '').toLowerCase();
    final hints = <Map<String, Object?>>[];
    for (final table in tables) {
      if (table is! Map) continue;
      final name = '${table['name'] ?? ''}';
      if (name.isEmpty) continue;
      if (prefix.isNotEmpty && !name.toLowerCase().startsWith(prefix)) {
        continue;
      }
      hints.add({
        'label': name,
        'kind': 'table',
        'detail': table['detail'],
      });
      final columns = table['columns'];
      if (columns is List) {
        for (final col in columns) {
          final colName = '$col';
          if (prefix.isNotEmpty &&
              !colName.toLowerCase().startsWith(prefix) &&
              !'$name.$colName'.toLowerCase().startsWith(prefix)) {
            continue;
          }
          hints.add({
            'label': colName,
            'kind': 'column',
            'detail': name,
          });
        }
      }
    }
    return EmbeddedInvokeResult.success(hints);
  }

  EmbeddedInvokeResult _sqlParse(
    Map<String, dynamic> module,
    Map<String, Object?> args,
  ) {
    final sql = args['sql'];
    if (sql is! String) {
      return EmbeddedInvokeResult.failure('sql.parse requires args.sql string.');
    }
    final trimmed = sql.trim();
    final first = trimmed.split(RegExp(r'\s+')).first.toUpperCase();
    final dialect = module['dialect'] as String? ?? 'generic';
    return EmbeddedInvokeResult.success({
      'dialect': dialect,
      'statement': first,
      'length': trimmed.length,
      'raw': trimmed,
    });
  }

  /// Strips `//` and `/* */` comments then `jsonDecode`s an object.
  static Map<String, dynamic> _parseJsoncObject(String source) {
    final withoutBlock = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final withoutLine = withoutBlock.replaceAll(RegExp(r'//[^\n]*'), '');
    final decoded = jsonDecode(withoutLine);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Module root must be a JSON object.');
    }
    return decoded;
  }
}
