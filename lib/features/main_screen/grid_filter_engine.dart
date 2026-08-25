/// Client-side filter engine for Data Grid.
///
/// Evaluates complex multi-clause expressions with AND / OR / NOT, parentheses,
/// column predicates (`col = val`, `col > 10`, `col LIKE '%test%'`, `col IN ('a', 'b')`,
/// `col IS NULL`, `col BETWEEN x AND y`), and free-text substring search.
abstract final class GridFilterEngine {
  /// Evaluates [filterText] against [rows] with respect to [columns].
  /// Returns the list of matching row indices.
  static List<int> filterRowIndices({
    required String filterText,
    required List<String> columns,
    required List<List<String>> rows,
  }) {
    final trimmed = filterText.trim();
    if (trimmed.isEmpty || columns.isEmpty || rows.isEmpty) {
      return List<int>.generate(rows.length, (i) => i);
    }

    final lowerColumns = columns.map((c) => c.toLowerCase()).toList();

    try {
      final tokens = _FilterLexer.tokenize(trimmed, lowerColumns);
      if (tokens.isEmpty) {
        return List<int>.generate(rows.length, (i) => i);
      }

      final parser = _FilterParser(tokens);
      final ast = parser.parse();

      if (ast == null) {
        return _fallbackSubstringFilter(trimmed, rows);
      }

      final matchingIndices = <int>[];
      for (var r = 0; r < rows.length; r++) {
        final row = rows[r];
        if (ast.evaluate(row, lowerColumns)) {
          matchingIndices.add(r);
        }
      }
      return matchingIndices;
    } catch (_) {
      // Graceful fallback to multi-term substring match if syntax has parse errors
      return _fallbackSubstringFilter(trimmed, rows);
    }
  }

  static List<int> _fallbackSubstringFilter(String input, List<List<String>> rows) {
    final terms = input.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (terms.isEmpty) {
      return List<int>.generate(rows.length, (i) => i);
    }

    final result = <int>[];
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      var matchAll = true;
      for (final term in terms) {
        var termMatch = false;
        for (var c = 0; c < row.length; c++) {
          if (row[c].toLowerCase().contains(term)) {
            termMatch = true;
            break;
          }
        }
        if (!termMatch) {
          matchAll = false;
          break;
        }
      }
      if (matchAll) {
        result.add(r);
      }
    }
    return result;
  }
}

// -----------------------------------------------------------------------------
// AST Nodes
// -----------------------------------------------------------------------------

abstract class _FilterAstNode {
  const _FilterAstNode();
  bool evaluate(List<String> row, List<String> lowerColumns);
}

class _AndNode extends _FilterAstNode {
  const _AndNode(this.left, this.right);
  final _FilterAstNode left;
  final _FilterAstNode right;

  @override
  bool evaluate(List<String> row, List<String> lowerColumns) {
    return left.evaluate(row, lowerColumns) && right.evaluate(row, lowerColumns);
  }
}

class _OrNode extends _FilterAstNode {
  const _OrNode(this.left, this.right);
  final _FilterAstNode left;
  final _FilterAstNode right;

  @override
  bool evaluate(List<String> row, List<String> lowerColumns) {
    return left.evaluate(row, lowerColumns) || right.evaluate(row, lowerColumns);
  }
}

class _NotNode extends _FilterAstNode {
  const _NotNode(this.child);
  final _FilterAstNode child;

  @override
  bool evaluate(List<String> row, List<String> lowerColumns) {
    return !child.evaluate(row, lowerColumns);
  }
}

class _PredicateNode extends _FilterAstNode {
  const _PredicateNode({
    required this.colIndex,
    required this.op,
    required this.targetValue,
    this.inValues = const [],
    this.betweenMin,
    this.betweenMax,
  });

  final int colIndex;
  final String op;
  final String targetValue;
  final List<String> inValues;
  final String? betweenMin;
  final String? betweenMax;

  @override
  bool evaluate(List<String> row, List<String> lowerColumns) {
    if (colIndex < 0 || colIndex >= row.length) return false;
    final cellValue = row[colIndex];
    final isNull = cellValue == 'NULL' || cellValue == 'null' || cellValue.isEmpty;
    final upperOp = op.toUpperCase().trim();

    // IS NULL / IS NOT NULL
    if (upperOp == 'IS NULL') {
      return isNull;
    }
    if (upperOp == 'IS NOT NULL') {
      return !isNull;
    }

    // IN / NOT IN
    if (upperOp == 'IN') {
      final lowerCell = cellValue.toLowerCase().trim();
      return inValues.any((v) => v.toLowerCase().trim() == lowerCell);
    }
    if (upperOp == 'NOT IN') {
      final lowerCell = cellValue.toLowerCase().trim();
      return !inValues.any((v) => v.toLowerCase().trim() == lowerCell);
    }

    // BETWEEN x AND y
    if (upperOp == 'BETWEEN' && betweenMin != null && betweenMax != null) {
      final numCell = double.tryParse(cellValue.trim());
      final numMin = double.tryParse(betweenMin!.trim());
      final numMax = double.tryParse(betweenMax!.trim());
      if (numCell != null && numMin != null && numMax != null) {
        return numCell >= numMin && numCell <= numMax;
      }
      return cellValue.compareTo(betweenMin!) >= 0 && cellValue.compareTo(betweenMax!) <= 0;
    }

    // LIKE / NOT LIKE
    if (upperOp == 'LIKE') {
      final regex = _likeToRegExp(targetValue, caseSensitive: true);
      return regex.hasMatch(cellValue);
    }
    if (upperOp == 'NOT LIKE') {
      final regex = _likeToRegExp(targetValue, caseSensitive: true);
      return !regex.hasMatch(cellValue);
    }

    // ILIKE / NOT ILIKE
    if (upperOp == 'ILIKE') {
      final regex = _likeToRegExp(targetValue, caseSensitive: false);
      return regex.hasMatch(cellValue);
    }
    if (upperOp == 'NOT ILIKE') {
      final regex = _likeToRegExp(targetValue, caseSensitive: false);
      return !regex.hasMatch(cellValue);
    }

    final lowerCell = cellValue.toLowerCase();
    final lowerTarget = targetValue.toLowerCase();

    // Numeric comparison if both values can be parsed as numbers
    final numCell = double.tryParse(cellValue.trim());
    final numTarget = double.tryParse(targetValue.trim());

    if (numCell != null && numTarget != null) {
      switch (op) {
        case '=':
        case '==':
        case ':':
          return (numCell - numTarget).abs() < 1e-9;
        case '!=':
        case '<>':
          return (numCell - numTarget).abs() >= 1e-9;
        case '>':
          return numCell > numTarget;
        case '>=':
          return numCell >= numTarget;
        case '<':
          return numCell < numTarget;
        case '<=':
          return numCell <= numTarget;
      }
    }

    // String / Lexicographic comparison
    switch (op) {
      case '=':
      case '==':
        return lowerCell == lowerTarget;
      case ':':
        return lowerCell.contains(lowerTarget);
      case '!=':
      case '<>':
        return lowerCell != lowerTarget;
      case '>':
        return lowerCell.compareTo(lowerTarget) > 0;
      case '>=':
        return lowerCell.compareTo(lowerTarget) >= 0;
      case '<':
        return lowerCell.compareTo(lowerTarget) < 0;
      case '<=':
        return lowerCell.compareTo(lowerTarget) <= 0;
      default:
        return lowerCell.contains(lowerTarget);
    }
  }

  static RegExp _likeToRegExp(String pattern, {required bool caseSensitive}) {
    final buffer = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      if (char == '%') {
        buffer.write('.*');
      } else if (char == '_') {
        buffer.write('.');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString(), caseSensitive: caseSensitive);
  }
}

class _FreeTextNode extends _FilterAstNode {
  const _FreeTextNode(this.term);
  final String term;

  @override
  bool evaluate(List<String> row, List<String> lowerColumns) {
    final lowerTerm = term.toLowerCase();
    for (var c = 0; c < row.length; c++) {
      if (row[c].toLowerCase().contains(lowerTerm)) {
        return true;
      }
    }
    return false;
  }
}

// -----------------------------------------------------------------------------
// Lexer
// -----------------------------------------------------------------------------

enum _TokenType {
  and,
  or,
  not,
  lparen,
  rparen,
  predicate,
  text,
}

class _FilterToken {
  const _FilterToken(this.type, {this.value = '', this.predicate});
  final _TokenType type;
  final String value;
  final _PredicateNode? predicate;
}

abstract final class _FilterLexer {
  static List<_FilterToken> tokenize(String input, List<String> lowerColumns) {
    final tokens = <_FilterToken>[];
    var i = 0;

    while (i < input.length) {
      // Skip whitespace
      if (input[i].trim().isEmpty) {
        i++;
        continue;
      }

      // Check for extended predicates with keywords (IS NULL, IS NOT NULL, LIKE, ILIKE, IN, BETWEEN)
      final remaining = input.substring(i);
      final kwPredicate = _tryMatchKeywordPredicate(remaining, lowerColumns);
      if (kwPredicate != null) {
        tokens.add(_FilterToken(_TokenType.predicate, predicate: kwPredicate.node));
        i += kwPredicate.consumedChars;
        continue;
      }

      // Parentheses
      if (input[i] == '(') {
        tokens.add(const _FilterToken(_TokenType.lparen, value: '('));
        i++;
        continue;
      }
      if (input[i] == ')') {
        tokens.add(const _FilterToken(_TokenType.rparen, value: ')'));
        i++;
        continue;
      }

      // Read next chunk/word until whitespace or parenthesis
      final start = i;
      while (i < input.length &&
          input[i].trim().isNotEmpty &&
          input[i] != '(' &&
          input[i] != ')') {
        // Handle quoted literals inside words
        if (input[i] == '\'' || input[i] == '"') {
          final quote = input[i];
          i++;
          while (i < input.length) {
            if (input[i] == '\\' && i + 1 < input.length) {
              i += 2;
            } else if (input[i] == quote) {
              if (i + 1 < input.length && input[i + 1] == quote) {
                // SQL-style doubled quote escape: ''
                i += 2;
              } else {
                i++; // closing quote
                break;
              }
            } else {
              i++;
            }
          }
        } else {
          i++;
        }
      }

      var word = input.substring(start, i).trim();
      if (word.isEmpty) continue;

      // Check logical operators
      final upper = word.toUpperCase();
      if (upper == 'AND' || word == '&&') {
        tokens.add(const _FilterToken(_TokenType.and, value: 'AND'));
        continue;
      }
      if (upper == 'OR' || word == '||') {
        tokens.add(const _FilterToken(_TokenType.or, value: 'OR'));
        continue;
      }
      if (upper == 'NOT' || word == '!') {
        tokens.add(const _FilterToken(_TokenType.not, value: 'NOT'));
        continue;
      }

      // Check if this token or upcoming sequence forms a predicate: col OP val
      final predicate = _tryExtractPredicate(word, lowerColumns);
      if (predicate != null) {
        tokens.add(_FilterToken(_TokenType.predicate, predicate: predicate));
        continue;
      }

      // If word is just a column name and the NEXT word is an operator (e.g. "amount", ">", "100")
      final colIdx = lowerColumns.indexOf(word.toLowerCase());
      if (colIdx != -1) {
        final rem = input.substring(i).trimLeft();
        final opMatch = RegExp(r'^(>=|<=|!=|<>|==|=|>|<|:)\s*([^\s()]+)')
            .firstMatch(rem);
        if (opMatch != null) {
          final op = opMatch.group(1)!;
          var val = opMatch.group(2)!;
          val = _stripQuotes(val);
          tokens.add(
            _FilterToken(
              _TokenType.predicate,
              predicate: _PredicateNode(
                colIndex: colIdx,
                op: op,
                targetValue: val,
              ),
            ),
          );
          i += input.substring(i).indexOf(opMatch.group(0)!) +
              opMatch.group(0)!.length;
          continue;
        }
      }

      word = _stripQuotes(word);
      tokens.add(_FilterToken(_TokenType.text, value: word));
    }

    return tokens;
  }

  static ({_PredicateNode node, int consumedChars})? _tryMatchKeywordPredicate(
    String remaining,
    List<String> lowerColumns,
  ) {
    // 1. IS NULL / IS NOT NULL (e.g. "status IS NULL", "email IS NOT NULL")
    final isNullMatch = RegExp(r'^([a-zA-Z_]\w*)\s+IS\s+(NOT\s+)?NULL\b', caseSensitive: false)
        .firstMatch(remaining);
    if (isNullMatch != null) {
      final colName = isNullMatch.group(1)!.toLowerCase();
      final colIdx = lowerColumns.indexOf(colName);
      if (colIdx != -1) {
        final isNot = isNullMatch.group(2) != null;
        return (
          node: _PredicateNode(
            colIndex: colIdx,
            op: isNot ? 'IS NOT NULL' : 'IS NULL',
            targetValue: '',
          ),
          consumedChars: isNullMatch.group(0)!.length,
        );
      }
    }

    // 2. IN / NOT IN (e.g. "status IN ('ACTIVE', 'PENDING')", "id NOT IN (1, 2, 3)")
    final inMatch = RegExp(r'^([a-zA-Z_]\w*)\s+(NOT\s+)?IN\s*\(([^)]+)\)', caseSensitive: false)
        .firstMatch(remaining);
    if (inMatch != null) {
      final colName = inMatch.group(1)!.toLowerCase();
      final colIdx = lowerColumns.indexOf(colName);
      if (colIdx != -1) {
        final isNot = inMatch.group(2) != null;
        final listStr = inMatch.group(3)!;
        final items = listStr
            .split(',')
            .map((s) => _stripQuotes(s.trim()))
            .where((s) => s.isNotEmpty)
            .toList();
        return (
          node: _PredicateNode(
            colIndex: colIdx,
            op: isNot ? 'NOT IN' : 'IN',
            targetValue: '',
            inValues: items,
          ),
          consumedChars: inMatch.group(0)!.length,
        );
      }
    }

    // 3. BETWEEN x AND y (e.g. "amount BETWEEN 10 AND 100")
    final betweenMatch = RegExp(r'^([a-zA-Z_]\w*)\s+BETWEEN\s+([^\s]+)\s+AND\s+([^\s()]+)', caseSensitive: false)
        .firstMatch(remaining);
    if (betweenMatch != null) {
      final colName = betweenMatch.group(1)!.toLowerCase();
      final colIdx = lowerColumns.indexOf(colName);
      if (colIdx != -1) {
        final minVal = _stripQuotes(betweenMatch.group(2)!.trim());
        final maxVal = _stripQuotes(betweenMatch.group(3)!.trim());
        return (
          node: _PredicateNode(
            colIndex: colIdx,
            op: 'BETWEEN',
            targetValue: '',
            betweenMin: minVal,
            betweenMax: maxVal,
          ),
          consumedChars: betweenMatch.group(0)!.length,
        );
      }
    }

    // 4. LIKE / ILIKE / NOT LIKE / NOT ILIKE (e.g. "name LIKE '%John%'", "email ILIKE '%.org'")
    final likeMatch = RegExp(r'^([a-zA-Z_]\w*)\s+(NOT\s+)?(ILIKE|LIKE)\s+([^\s()]+)', caseSensitive: false)
        .firstMatch(remaining);
    if (likeMatch != null) {
      final colName = likeMatch.group(1)!.toLowerCase();
      final colIdx = lowerColumns.indexOf(colName);
      if (colIdx != -1) {
        final isNot = likeMatch.group(2) != null;
        final likeType = likeMatch.group(3)!.toUpperCase();
        final pattern = _stripQuotes(likeMatch.group(4)!.trim());
        final op = isNot ? 'NOT $likeType' : likeType;
        return (
          node: _PredicateNode(
            colIndex: colIdx,
            op: op,
            targetValue: pattern,
          ),
          consumedChars: likeMatch.group(0)!.length,
        );
      }
    }

    return null;
  }

  static _PredicateNode? _tryExtractPredicate(
    String token,
    List<String> lowerColumns,
  ) {
    const ops = ['>=', '<=', '!=', '<>', '==', '=', '>', '<', ':'];
    for (final op in ops) {
      final parts = token.split(op);
      if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        final colCandidate = parts[0].trim().toLowerCase();
        final colIdx = lowerColumns.indexOf(colCandidate);
        if (colIdx != -1) {
          final val = _stripQuotes(parts[1].trim());
          return _PredicateNode(
            colIndex: colIdx,
            op: op,
            targetValue: val,
          );
        }
      }
    }
    return null;
  }

  static String _stripQuotes(String s) {
    if ((s.startsWith("'") && s.endsWith("'")) ||
        (s.startsWith('"') && s.endsWith('"'))) {
      if (s.length >= 2) {
        return s
            .substring(1, s.length - 1)
            .replaceAll("''", "'")
            .replaceAll(r"\'", "'")
            .replaceAll(r'\"', '"');
      }
    }
    return s;
  }
}

// -----------------------------------------------------------------------------
// Parser
// -----------------------------------------------------------------------------

class _FilterParser {
  _FilterParser(this.tokens);
  final List<_FilterToken> tokens;
  int _pos = 0;

  _FilterAstNode? parse() {
    if (tokens.isEmpty) return null;
    return _parseOr();
  }

  _FilterAstNode _parseOr() {
    var node = _parseAnd();
    while (_match(_TokenType.or)) {
      final right = _parseAnd();
      node = _OrNode(node, right);
    }
    return node;
  }

  _FilterAstNode _parseAnd() {
    var node = _parseUnary();
    while (_match(_TokenType.and) || _isImplicitAnd()) {
      final right = _parseUnary();
      node = _AndNode(node, right);
    }
    return node;
  }

  bool _isImplicitAnd() {
    if (_pos >= tokens.length) return false;
    final type = tokens[_pos].type;
    return type == _TokenType.predicate ||
        type == _TokenType.text ||
        type == _TokenType.lparen ||
        type == _TokenType.not;
  }

  _FilterAstNode _parseUnary() {
    if (_match(_TokenType.not)) {
      return _NotNode(_parseUnary());
    }
    return _parsePrimary();
  }

  _FilterAstNode _parsePrimary() {
    if (_match(_TokenType.lparen)) {
      final node = _parseOr();
      _consume(_TokenType.rparen);
      return node;
    }

    if (_pos < tokens.length) {
      final token = tokens[_pos++];
      if (token.type == _TokenType.predicate && token.predicate != null) {
        return token.predicate!;
      }
      return _FreeTextNode(token.value);
    }

    return const _FreeTextNode('');
  }

  bool _match(_TokenType type) {
    if (_pos < tokens.length && tokens[_pos].type == type) {
      _pos++;
      return true;
    }
    return false;
  }

  void _consume(_TokenType type) {
    if (_pos < tokens.length && tokens[_pos].type == type) {
      _pos++;
    }
  }
}
