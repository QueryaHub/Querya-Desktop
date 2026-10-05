import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;

/// Recognized MQL method types that can be invoked via the query console.
enum MqlMethod {
  find,
  findOne,
  count,
  countDocuments,
  aggregate,
  insertOne,
  insertMany,
  updateOne,
  updateMany,
  deleteOne,
  deleteMany,
  drop,
  runCommand,
  getCollectionNames,
  stats,
  unknown,
}

/// Parsed representation of an MQL query or shell statement.
class MqlCommand {
  const MqlCommand({
    required this.method,
    this.collection,
    this.filter,
    this.projection,
    this.sort,
    this.limit,
    this.skip,
    this.pipeline,
    this.document,
    this.documents,
    this.update,
    this.upsert = false,
    this.commandMap,
    this.rawText = '',
  });

  final MqlMethod method;
  final String? collection;
  final Map<String, dynamic>? filter;
  final Map<String, dynamic>? projection;
  final Map<String, dynamic>? sort;
  final int? limit;
  final int? skip;
  final List<Map<String, dynamic>>? pipeline;
  final Map<String, dynamic>? document;
  final List<Map<String, dynamic>>? documents;
  final Map<String, dynamic>? update;
  final bool upsert;
  final Map<String, dynamic>? commandMap;
  final String rawText;

  @override
  String toString() {
    return 'MqlCommand(method: $method, collection: $collection, filter: $filter, '
        'sort: $sort, limit: $limit, skip: $skip, pipeline: $pipeline)';
  }
}

/// Parser for MongoDB Query Language (MQL) and shell statements.
///
/// Supports:
/// - `db.<collection>.find({ ... })` with `.sort()`, `.limit()`, `.skip()`, `.projection()`
/// - `db.<collection>.findOne({ ... })`
/// - `db.<collection>.countDocuments({ ... })` or `.count()`
/// - `db.<collection>.aggregate([ ... ])`
/// - `db.<collection>.insertOne({ ... })`
/// - `db.<collection>.insertMany([ ... ])`
/// - `db.<collection>.updateOne({ ... }, { ... })`
/// - `db.<collection>.updateMany({ ... }, { ... })`
/// - `db.<collection>.deleteOne({ ... })`
/// - `db.<collection>.deleteMany({ ... })`
/// - `db.<collection>.drop()`
/// - `db.<collection>.stats()`
/// - `db.runCommand({ ... })`
/// - `db.getCollectionNames()`
/// - Direct JSON/EJSON object `{ "find": "...", ... }`
/// - Shorthand `<collection>.find(...)` without `db.`
class MqlParser {
  const MqlParser();

  /// Parses a raw MQL query string into an [MqlCommand].
  static MqlCommand parse(String input, {String? defaultCollection}) {
    var text = input.trim();
    if (text.endsWith(';')) {
      text = text.substring(0, text.length - 1).trim();
    }

    if (text.isEmpty) {
      throw const FormatException('Query cannot be empty');
    }

    // Direct JSON object (e.g. `{ "ping": 1 }` or `{ "find": "coll" }`)
    if (text.startsWith('{')) {
      final decoded = _parseRelaxedJson(text);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('find') && decoded['find'] is String) {
          final coll = decoded['find'] as String;
          final filter = decoded['filter'] is Map
              ? Map<String, dynamic>.from(decoded['filter'] as Map)
              : null;
          final sort = decoded['sort'] is Map
              ? Map<String, dynamic>.from(decoded['sort'] as Map)
              : null;
          final limit = decoded['limit'] is num
              ? (decoded['limit'] as num).toInt()
              : null;
          final skip = decoded['skip'] is num
              ? (decoded['skip'] as num).toInt()
              : null;
          return MqlCommand(
            method: MqlMethod.find,
            collection: coll,
            filter: filter,
            sort: sort,
            limit: limit,
            skip: skip,
            rawText: input,
          );
        }
        return MqlCommand(
          method: MqlMethod.runCommand,
          commandMap: decoded,
          rawText: input,
        );
      }
    }

    // Direct aggregation pipeline array: `[ { "$match": ... } ]`
    if (text.startsWith('[')) {
      final decoded = _parseRelaxedJson(text);
      if (decoded is List) {
        final pipeline = decoded
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        return MqlCommand(
          method: MqlMethod.aggregate,
          collection: defaultCollection,
          pipeline: pipeline,
          rawText: input,
        );
      }
    }

    // Remove leading `db.` if present
    if (text.startsWith('db.')) {
      text = text.substring(3).trim();
    }

    // Check for `runCommand(...)`
    if (text.startsWith('runCommand(')) {
      final argText = _extractFirstCallArguments(text, 'runCommand');
      final arg = _parseRelaxedJson(argText);
      if (arg is! Map) {
        throw const FormatException('runCommand argument must be a document');
      }
      return MqlCommand(
        method: MqlMethod.runCommand,
        commandMap: Map<String, dynamic>.from(arg),
        rawText: input,
      );
    }

    // Check for `getCollectionNames()`
    if (text == 'getCollectionNames()' || text == 'getCollectionNames') {
      return MqlCommand(
        method: MqlMethod.getCollectionNames,
        rawText: input,
      );
    }

    // Collection-level call: `<collection>.<method>(...)`
    final dotIndex = text.indexOf('.');
    if (dotIndex == -1) {
      throw FormatException('Invalid query format: $input');
    }

    final collectionName = text.substring(0, dotIndex).trim();
    final remainingCalls = text.substring(dotIndex + 1).trim();

    return _parseCollectionChain(
      collectionName: collectionName,
      chainText: remainingCalls,
      rawText: input,
    );
  }

  static MqlCommand _parseCollectionChain({
    required String collectionName,
    required String chainText,
    required String rawText,
  }) {
    // Parse chain of method calls: e.g. find(...).sort(...).limit(...)
    final calls = _splitMethodChain(chainText);
    if (calls.isEmpty) {
      throw FormatException('No method called on collection "$collectionName"');
    }

    final primaryCall = calls.first;
    final methodName = primaryCall.name;
    final rawArgs = primaryCall.argumentsText;

    MqlMethod method;
    switch (methodName) {
      case 'find':
        method = MqlMethod.find;
        break;
      case 'findOne':
        method = MqlMethod.findOne;
        break;
      case 'count':
        method = MqlMethod.count;
        break;
      case 'countDocuments':
        method = MqlMethod.countDocuments;
        break;
      case 'aggregate':
        method = MqlMethod.aggregate;
        break;
      case 'insertOne':
        method = MqlMethod.insertOne;
        break;
      case 'insertMany':
        method = MqlMethod.insertMany;
        break;
      case 'updateOne':
        method = MqlMethod.updateOne;
        break;
      case 'updateMany':
        method = MqlMethod.updateMany;
        break;
      case 'deleteOne':
        method = MqlMethod.deleteOne;
        break;
      case 'deleteMany':
        method = MqlMethod.deleteMany;
        break;
      case 'drop':
        method = MqlMethod.drop;
        break;
      case 'stats':
        method = MqlMethod.stats;
        break;
      default:
        throw FormatException('Unsupported collection method: $methodName');
    }

    final parsedArgs = _parseArgumentsList(rawArgs);

    Map<String, dynamic>? filter;
    Map<String, dynamic>? projection;
    Map<String, dynamic>? sort;
    int? limit;
    int? skip;
    List<Map<String, dynamic>>? pipeline;
    Map<String, dynamic>? document;
    List<Map<String, dynamic>>? documents;
    Map<String, dynamic>? update;

    switch (method) {
      case MqlMethod.find:
        if (parsedArgs.isNotEmpty && parsedArgs[0] is Map) {
          filter = Map<String, dynamic>.from(parsedArgs[0] as Map);
        }
        if (parsedArgs.length > 1 && parsedArgs[1] is Map) {
          projection = Map<String, dynamic>.from(parsedArgs[1] as Map);
        }
        break;

      case MqlMethod.findOne:
        if (parsedArgs.isNotEmpty && parsedArgs[0] is Map) {
          filter = Map<String, dynamic>.from(parsedArgs[0] as Map);
        }
        if (parsedArgs.length > 1 && parsedArgs[1] is Map) {
          projection = Map<String, dynamic>.from(parsedArgs[1] as Map);
        }
        limit = 1;
        break;

      case MqlMethod.count:
      case MqlMethod.countDocuments:
        if (parsedArgs.isNotEmpty && parsedArgs[0] is Map) {
          filter = Map<String, dynamic>.from(parsedArgs[0] as Map);
        }
        break;

      case MqlMethod.aggregate:
        if (parsedArgs.isNotEmpty && parsedArgs[0] is List) {
          pipeline = (parsedArgs[0] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        } else {
          pipeline = [];
        }
        break;

      case MqlMethod.insertOne:
        if (parsedArgs.isNotEmpty && parsedArgs[0] is Map) {
          document = Map<String, dynamic>.from(parsedArgs[0] as Map);
        } else {
          throw const FormatException('insertOne requires a document argument');
        }
        break;

      case MqlMethod.insertMany:
        if (parsedArgs.isNotEmpty && parsedArgs[0] is List) {
          documents = (parsedArgs[0] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        } else {
          throw const FormatException(
              'insertMany requires an array of documents');
        }
        break;

      case MqlMethod.updateOne:
      case MqlMethod.updateMany:
        if (parsedArgs.length >= 2 &&
            parsedArgs[0] is Map &&
            parsedArgs[1] is Map) {
          filter = Map<String, dynamic>.from(parsedArgs[0] as Map);
          update = Map<String, dynamic>.from(parsedArgs[1] as Map);
        } else {
          throw FormatException(
              '$methodName requires filter and update documents');
        }
        break;

      case MqlMethod.deleteOne:
      case MqlMethod.deleteMany:
        if (parsedArgs.isNotEmpty && parsedArgs[0] is Map) {
          filter = Map<String, dynamic>.from(parsedArgs[0] as Map);
        } else {
          throw FormatException(
              '$methodName requires a filter document argument');
        }
        break;

      default:
        break;
    }

    // Process secondary chained methods: .sort(), .limit(), .skip(), .count(), .project()
    for (var i = 1; i < calls.length; i++) {
      final call = calls[i];
      final cArgs = _parseArgumentsList(call.argumentsText);

      switch (call.name) {
        case 'sort':
          if (cArgs.isNotEmpty && cArgs[0] is Map) {
            sort = Map<String, dynamic>.from(cArgs[0] as Map);
          }
          break;
        case 'limit':
          if (cArgs.isNotEmpty && cArgs[0] is num) {
            limit = (cArgs[0] as num).toInt();
          }
          break;
        case 'skip':
          if (cArgs.isNotEmpty && cArgs[0] is num) {
            skip = (cArgs[0] as num).toInt();
          }
          break;
        case 'project':
        case 'projection':
          if (cArgs.isNotEmpty && cArgs[0] is Map) {
            projection = Map<String, dynamic>.from(cArgs[0] as Map);
          }
          break;
        case 'count':
          method = MqlMethod.count;
          break;
      }
    }

    return MqlCommand(
      method: method,
      collection: collectionName,
      filter: filter,
      projection: projection,
      sort: sort,
      limit: limit,
      skip: skip,
      pipeline: pipeline,
      document: document,
      documents: documents,
      update: update,
      rawText: rawText,
    );
  }

  // ─── Method Chain Splitting ──────────────────────────────────────────────────

  static List<_CallInfo> _splitMethodChain(String input) {
    final result = <_CallInfo>[];
    var index = 0;

    while (index < input.length) {
      if (input[index] == '.') {
        index++;
      }
      while (index < input.length && input[index].trim().isEmpty) {
        index++;
      }
      if (index >= input.length) break;

      final openParen = input.indexOf('(', index);
      if (openParen == -1) break;

      final methodName = input.substring(index, openParen).trim();
      final closeParen = _findMatchingParen(input, openParen);
      if (closeParen == -1) {
        throw FormatException('Unclosed parenthesis in: $input');
      }

      final argsContent = input.substring(openParen + 1, closeParen).trim();
      result.add(_CallInfo(name: methodName, argumentsText: argsContent));
      index = closeParen + 1;
    }

    return result;
  }

  static int _findMatchingParen(String text, int openIndex) {
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    var escaped = false;

    for (var i = openIndex; i < text.length; i++) {
      final char = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == "'" && !inDouble) {
        inSingle = !inSingle;
        continue;
      }
      if (char == '"' && !inSingle) {
        inDouble = !inDouble;
        continue;
      }
      if (inSingle || inDouble) continue;

      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static String _extractFirstCallArguments(String text, String methodName) {
    final startIdx = text.indexOf('$methodName(');
    if (startIdx == -1) return '';
    final openParen = startIdx + methodName.length;
    final closeParen = _findMatchingParen(text, openParen);
    if (closeParen == -1) return '';
    return text.substring(openParen + 1, closeParen).trim();
  }

  // ─── Argument Splitting & Parsing ────────────────────────────────────────────

  static List<dynamic> _parseArgumentsList(String argsText) {
    final trimmed = argsText.trim();
    if (trimmed.isEmpty) return [];

    final rawArgs = _splitTopLevelArguments(trimmed);
    return rawArgs.map((a) => _parseRelaxedJson(a.trim())).toList();
  }

  static List<String> _splitTopLevelArguments(String text) {
    final result = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    var escaped = false;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }
      if (char == r'\') {
        buffer.write(char);
        escaped = true;
        continue;
      }
      if (char == "'" && !inDouble) {
        inSingle = !inSingle;
        buffer.write(char);
        continue;
      }
      if (char == '"' && !inSingle) {
        inDouble = !inDouble;
        buffer.write(char);
        continue;
      }

      if (!inSingle && !inDouble) {
        if (char == '{' || char == '[' || char == '(') {
          depth++;
        } else if (char == '}' || char == ']' || char == ')') {
          depth--;
        } else if (char == ',' && depth == 0) {
          result.add(buffer.toString());
          buffer.clear();
          continue;
        }
      }

      buffer.write(char);
    }

    if (buffer.isNotEmpty) {
      result.add(buffer.toString());
    }

    return result;
  }

  // ─── Relaxed JSON / JS Object Literal Parser ────────────────────────────────

  static dynamic _parseRelaxedJson(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // Check for constructor functions e.g. ObjectId("..."), ISODate("...")
    if (trimmed.startsWith('ObjectId(') && trimmed.endsWith(')')) {
      final hex = trimmed
          .substring(9, trimmed.length - 1)
          .replaceAll(RegExp(r'''['"]'''), '');
      return ObjectId.fromHexString(hex);
    }
    if (trimmed.startsWith('ISODate(') && trimmed.endsWith(')')) {
      final iso = trimmed
          .substring(8, trimmed.length - 1)
          .replaceAll(RegExp(r'''['"]'''), '');
      return DateTime.parse(iso);
    }
    if ((trimmed.startsWith('NumberLong(') || trimmed.startsWith('NumberInt(')) &&
        trimmed.endsWith(')')) {
      final numStr = trimmed
          .substring(trimmed.indexOf('(') + 1, trimmed.length - 1)
          .replaceAll(RegExp(r'''['"]'''), '');
      return int.parse(numStr);
    }
    if (trimmed.startsWith('RegExp(') && trimmed.endsWith(')')) {
      final args = trimmed.substring(7, trimmed.length - 1).split(',');
      final pattern = args[0].trim().replaceAll(RegExp(r'''['"]'''), '');
      return RegExp(pattern);
    }

    // Try standard JSON decode first
    try {
      return json.decode(trimmed);
    } catch (_) {
      // Fallback to relaxed JS object parsing
    }

    final normalized = _normalizeJsObject(trimmed);
    return json.decode(normalized);
  }

  /// Normalizes JavaScript object literal syntax into valid JSON:
  /// - Quote unquoted keys: `{ foo: "bar" }` -> `{ "foo": "bar" }`
  /// - Single quotes to double quotes: `'foo'` -> `"foo"`
  /// - Constructor function handling inside objects/arrays
  static String _normalizeJsObject(String input) {
    var s = input;

    // Replace ObjectId("hex") with {"$oid": "hex"}
    s = s.replaceAllMapped(
      RegExp(r'ObjectId\s*\(\s*["\x27]([0-9a-fA-F]{24})["\x27]\s*\)'),
      (m) => '{"\$oid":"${m[1]}"}',
    );

    // Replace ISODate("...") with {"$date": "..."}
    s = s.replaceAllMapped(
      RegExp(r'ISODate\s*\(\s*["\x27]([^"\x27]+)["\x27]\s*\)'),
      (m) => '{"\$date":"${m[1]}"}',
    );

    // Replace NumberLong(...) / NumberInt(...) with numeric literal
    s = s.replaceAllMapped(
      RegExp(r'(?:NumberLong|NumberInt)\s*\(\s*["\x27]?(\d+)["\x27]?\s*\)'),
      (m) => '${m[1]}',
    );

    // Tokenize strings to preserve quotes and contents
    final strings = <String>[];
    final tokenized = StringBuffer();
    var inSingle = false;
    var inDouble = false;
    var escaped = false;
    var currentStr = StringBuffer();

    for (var i = 0; i < s.length; i++) {
      final char = s[i];
      if (escaped) {
        currentStr.write(char);
        escaped = false;
        continue;
      }
      if (char == r'\') {
        currentStr.write(char);
        escaped = true;
        continue;
      }
      if (char == "'" && !inDouble) {
        if (inSingle) {
          inSingle = false;
          final placeholder = '@@@STR_${strings.length}@@@';
          strings.add(json.encode(currentStr.toString()));
          tokenized.write(placeholder);
          currentStr.clear();
        } else {
          inSingle = true;
        }
        continue;
      }
      if (char == '"' && !inSingle) {
        if (inDouble) {
          inDouble = false;
          final placeholder = '@@@STR_${strings.length}@@@';
          strings.add(json.encode(currentStr.toString()));
          tokenized.write(placeholder);
          currentStr.clear();
        } else {
          inDouble = true;
        }
        continue;
      }

      if (inSingle || inDouble) {
        currentStr.write(char);
      } else {
        tokenized.write(char);
      }
    }

    var processed = tokenized.toString();

    // Quote unquoted object keys: e.g. `{ key: ` or `, key: `
    processed = processed.replaceAllMapped(
      RegExp(r'([{\[,]\s*)([a-zA-Z0-9_\$]+)\s*:'),
      (m) => '${m[1]}"${m[2]}":',
    );

    // Restore strings
    for (var i = 0; i < strings.length; i++) {
      processed = processed.replaceAll('@@@STR_$i@@@', strings[i]);
    }

    return processed;
  }
}

class _CallInfo {
  const _CallInfo({required this.name, required this.argumentsText});
  final String name;
  final String argumentsText;
}
