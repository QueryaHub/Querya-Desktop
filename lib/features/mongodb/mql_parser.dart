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

  /// Normalizes a mongosh object literal into JSON, in one pass over [input]
  /// (#1513, #1539):
  /// - unquoted keys after `{`, `[` or `,` are quoted: `{ foo: 1 }`;
  /// - `'single'` and `"double"` strings become JSON strings, with their
  ///   JavaScript escapes (`\n`, `\'`, `\"`, `\\`, `\xXX`, `\uXXXX`) decoded;
  /// - outside strings only: `ObjectId("hex")` -> `{"$oid":"hex"}`,
  ///   `ISODate("...")` -> `{"$date":"..."}`, `NumberLong(n)` / `NumberInt(n)`
  ///   -> `n`.
  ///
  /// It used to swap strings for `@@@STR_n@@@` markers and put them back with
  /// one `replaceAll` over the whole query per string: quadratic (an
  /// `insertMany` of 1,000 documents took over a second), and a string that
  /// contained a marker, a constructor call or an escape came out changed.
  static String _normalizeJsObject(String input) {
    final out = StringBuffer();
    final n = input.length;
    var i = 0;
    var prev = -1; // the last non-blank code unit written
    while (i < n) {
      final c = input.codeUnitAt(i);
      if (c == 0x22 || c == 0x27) {
        final str = _scanJsString(input, i);
        if (str == null) {
          // Unterminated: left as typed, for json.decode to report.
          out.write(input.substring(i));
          break;
        }
        out.write(json.encode(str.value));
        prev = 0x22;
        i = str.end;
        continue;
      }
      if (_isWordChar(c)) {
        var j = i + 1;
        while (j < n && _isWordChar(input.codeUnitAt(j))) {
          j++;
        }
        final word = input.substring(i, j);
        final call = _scanBsonCall(input, word, j);
        if (call != null) {
          out.write(call.json);
          prev = 0x7D;
          i = call.end;
          continue;
        }
        final next = _skipBlanks(input, j);
        final isKey = (prev == 0x7B || prev == 0x5B || prev == 0x2C) &&
            next < n &&
            input.codeUnitAt(next) == 0x3A;
        if (isKey) {
          out
            ..write('"')
            ..write(word)
            ..write('"');
        } else {
          out.write(word);
        }
        prev = word.codeUnitAt(word.length - 1);
        i = j;
        continue;
      }
      out.writeCharCode(c);
      if (!_isBlank(c)) prev = c;
      i++;
    }
    return out.toString();
  }

  /// `[A-Za-z0-9_$]`: what an unquoted key, `true` / `null` or a number's
  /// digits are made of.
  static bool _isWordChar(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x24;

  static bool _isBlank(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  static int _skipBlanks(String s, int i) {
    while (i < s.length && _isBlank(s.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  /// The JavaScript string literal that opens at [start] (`'` or `"`): its
  /// value with the escapes decoded, and the offset after the closing quote.
  /// Null when it is never closed.
  static ({String value, int end})? _scanJsString(String s, int start) {
    final quote = s.codeUnitAt(start);
    final value = StringBuffer();
    var i = start + 1;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == quote) return (value: value.toString(), end: i + 1);
      if (c != 0x5C || i + 1 >= s.length) {
        value.writeCharCode(c);
        i++;
        continue;
      }
      final e = s.codeUnitAt(i + 1);
      i += 2;
      switch (e) {
        case 0x6E: // n
          value.writeCharCode(0x0A);
        case 0x74: // t
          value.writeCharCode(0x09);
        case 0x72: // r
          value.writeCharCode(0x0D);
        case 0x62: // b
          value.writeCharCode(0x08);
        case 0x66: // f
          value.writeCharCode(0x0C);
        case 0x76: // v
          value.writeCharCode(0x0B);
        case 0x30 when i >= s.length || !_isDigit(s.codeUnitAt(i)): // \0
          value.writeCharCode(0x00);
        case 0x78 || 0x75: // x, u
          final braced = e == 0x75 && i < s.length && s.codeUnitAt(i) == 0x7B;
          final close = braced ? s.indexOf('}', i) : -1;
          final from = braced ? i + 1 : i;
          final to = braced ? close : i + (e == 0x78 ? 2 : 4);
          final code = to > from && to <= s.length
              ? int.tryParse(s.substring(from, to), radix: 16)
              : null;
          if (code == null) {
            value.writeCharCode(e); // not a valid escape: the letter itself
          } else {
            value.writeCharCode(code);
            i = braced ? close + 1 : to;
          }
        case 0x0D: // line continuation, \r\n or \r
          if (i < s.length && s.codeUnitAt(i) == 0x0A) i++;
        case 0x0A: // line continuation
          break;
        default: // \' \" \\ \/ and any other character stand for themselves
          value.writeCharCode(e);
      }
    }
    return null;
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  /// `ObjectId(...)`, `ISODate(...)`, `NumberLong(...)` or `NumberInt(...)`
  /// right after [word] (which ends at [at]), as JSON, and the offset after
  /// its `)`. Null when [word] is not one of them or the call does not have
  /// the expected argument; the text is then kept as typed, as before.
  static ({String json, int end})? _scanBsonCall(
    String s,
    String word,
    int at,
  ) {
    if (word != 'ObjectId' &&
        word != 'ISODate' &&
        word != 'NumberLong' &&
        word != 'NumberInt') {
      return null;
    }
    var i = _skipBlanks(s, at);
    if (i >= s.length || s.codeUnitAt(i) != 0x28) return null; // (
    i = _skipBlanks(s, i + 1);
    if (i >= s.length) return null;
    String? arg;
    final c = s.codeUnitAt(i);
    if (c == 0x22 || c == 0x27) {
      final str = _scanJsString(s, i);
      if (str == null) return null;
      arg = str.value;
      i = str.end;
    } else if (word.startsWith('Number')) {
      final from = i;
      if (s.codeUnitAt(i) == 0x2D) i++; // -
      while (i < s.length && _isDigit(s.codeUnitAt(i))) {
        i++;
      }
      arg = s.substring(from, i);
    }
    if (arg == null) return null;
    i = _skipBlanks(s, i);
    if (i >= s.length || s.codeUnitAt(i) != 0x29) return null; // )
    final end = i + 1;
    switch (word) {
      case 'ObjectId':
        if (!_objectIdHex.hasMatch(arg)) return null;
        return (json: '{"\$oid":${json.encode(arg)}}', end: end);
      case 'ISODate':
        if (arg.isEmpty) return null;
        return (json: '{"\$date":${json.encode(arg)}}', end: end);
      default:
        if (!_integer.hasMatch(arg)) return null;
        return (json: arg, end: end);
    }
  }

  static final RegExp _objectIdHex = RegExp(r'^[0-9a-fA-F]{24}$');
  static final RegExp _integer = RegExp(r'^-?\d+$');
}

class _CallInfo {
  const _CallInfo({required this.name, required this.argumentsText});
  final String name;
  final String argumentsText;
}
