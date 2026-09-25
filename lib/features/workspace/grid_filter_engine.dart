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

      // Check logical operators: AND, &&, OR, ||, NOT, !
      final rem = input.substring(i);
      final andMatch =
          RegExp(r'^(AND\b|&&)', caseSensitive: false).firstMatch(rem);
      if (andMatch != null) {
        tokens.add(const _FilterToken(_TokenType.and, value: 'AND'));
        i += andMatch.group(0)!.length;
        continue;
      }

      final orMatch =
          RegExp(r'^(OR\b|\|\|)', caseSensitive: false).firstMatch(rem);
      if (orMatch != null) {
        tokens.add(const _FilterToken(_TokenType.or, value: 'OR'));
        i += orMatch.group(0)!.length;
        continue;
      }

      final notMatch =
          RegExp(r'^(NOT\b|!)', caseSensitive: false).firstMatch(rem);
      if (notMatch != null) {
        tokens.add(const _FilterToken(_TokenType.not, value: 'NOT'));
        i += notMatch.group(0)!.length;
        continue;
      }

      // Check for predicate (col OP val, col LIKE pat, col IS NULL, etc.)
      final predicate = _tryMatchPredicate(input, i, lowerColumns);
      if (predicate != null) {
        tokens.add(
          _FilterToken(_TokenType.predicate, predicate: predicate.node),
        );
        i += predicate.consumedChars;
        continue;
      }

      // Otherwise parse next value / word as free-text token
      final valParsed = _parseValue(input, i);
      if (valParsed != null && valParsed.consumedChars > 0) {
        tokens.add(_FilterToken(_TokenType.text, value: valParsed.value));
        i += valParsed.consumedChars;
        continue;
      }

      i++;
    }

    return tokens;
  }

  static ({_PredicateNode node, int consumedChars})? _tryMatchPredicate(
    String input,
    int start,
    List<String> lowerColumns,
  ) {
    final colParsed = _parseColumnIdentifier(input, start, lowerColumns);
    if (colParsed == null) return null;

    final colIdx = colParsed.colIndex;
    var p = start + colParsed.consumedChars;

    final isQuotedCol = input[start] == '"' || input[start] == '`';
    final spaceStart = p;
    while (p < input.length && input[p].trim().isEmpty) {
      p++;
    }
    if (p >= input.length) return null;

    final hadSpace = p > spaceStart;
    final canMatchKeyword = hadSpace || isQuotedCol;
    final rem = input.substring(p);

    // 1. IS NULL / IS NOT NULL
    if (canMatchKeyword) {
      final isNullMatch =
          RegExp(r'^IS\s+(NOT\s+)?NULL\b', caseSensitive: false).firstMatch(rem);
      if (isNullMatch != null) {
        final isNot = isNullMatch.group(1) != null;
        return (
          node: _PredicateNode(
            colIndex: colIdx,
            op: isNot ? 'IS NOT NULL' : 'IS NULL',
            targetValue: '',
          ),
          consumedChars: (p - start) + isNullMatch.group(0)!.length,
        );
      }
    }

    // 2. IN / NOT IN
    if (canMatchKeyword) {
      final inMatch =
          RegExp(r'^(NOT\s+)?IN\s*\(', caseSensitive: false).firstMatch(rem);
      if (inMatch != null) {
        final isNot = inMatch.group(1) != null;
        var inPos = p + inMatch.group(0)!.length;
        final items = <String>[];
        while (inPos < input.length) {
          while (inPos < input.length &&
              (input[inPos].trim().isEmpty || input[inPos] == ',')) {
            inPos++;
          }
          if (inPos < input.length && input[inPos] == ')') {
            inPos++;
            break;
          }
          final itemVal = _parseValue(input, inPos);
          if (itemVal == null || itemVal.consumedChars == 0) {
            break;
          }
          items.add(itemVal.value);
          inPos += itemVal.consumedChars;
        }
        return (
          node: _PredicateNode(
            colIndex: colIdx,
            op: isNot ? 'NOT IN' : 'IN',
            targetValue: '',
            inValues: items,
          ),
          consumedChars: inPos - start,
        );
      }
    }

    // 3. BETWEEN x AND y
    if (canMatchKeyword) {
      final betweenMatch =
          RegExp(r'^BETWEEN\s+', caseSensitive: false).firstMatch(rem);
      if (betweenMatch != null) {
        var bPos = p + betweenMatch.group(0)!.length;
        final minVal = _parseValue(input, bPos);
        if (minVal != null) {
          bPos += minVal.consumedChars;
          var andPos = bPos;
          while (andPos < input.length && input[andPos].trim().isEmpty) {
            andPos++;
          }
          final andRem = input.substring(andPos);
          final andMatch =
              RegExp(r'^AND\s+', caseSensitive: false).firstMatch(andRem);
          if (andMatch != null) {
            var maxPos = andPos + andMatch.group(0)!.length;
            final maxVal = _parseValue(input, maxPos);
            if (maxVal != null) {
              maxPos += maxVal.consumedChars;
              return (
                node: _PredicateNode(
                  colIndex: colIdx,
                  op: 'BETWEEN',
                  targetValue: '',
                  betweenMin: minVal.value,
                  betweenMax: maxVal.value,
                ),
                consumedChars: maxPos - start,
              );
            }
          }
        }
      }
    }

    // 4. LIKE / ILIKE / NOT LIKE / NOT ILIKE
    if (canMatchKeyword) {
      final likeMatch =
          RegExp(r'^(NOT\s+)?(ILIKE|LIKE)\s+', caseSensitive: false)
              .firstMatch(rem);
      if (likeMatch != null) {
        final isNot = likeMatch.group(1) != null;
        final likeType = likeMatch.group(2)!.toUpperCase();
        final lPos = p + likeMatch.group(0)!.length;
        final patVal = _parseValue(input, lPos);
        if (patVal != null) {
          final op = isNot ? 'NOT $likeType' : likeType;
          return (
            node: _PredicateNode(
              colIndex: colIdx,
              op: op,
              targetValue: patVal.value,
            ),
            consumedChars: (lPos - start) + patVal.consumedChars,
          );
        }
      }
    }

    // 5. Comparison operators: >=, <=, !=, <>, ==, =, >, <, :
    final opMatch =
        RegExp(r'^(>=|<=|!=|<>|==|=|>|<|:)').firstMatch(rem);
    if (opMatch != null) {
      final op = opMatch.group(1)!;
      final oPos = p + opMatch.group(0)!.length;
      final valParsed = _parseValue(input, oPos);
      if (valParsed != null) {
        return (
          node: _PredicateNode(
            colIndex: colIdx,
            op: op,
            targetValue: valParsed.value,
          ),
          consumedChars: (oPos - start) + valParsed.consumedChars,
        );
      }
    }

    return null;
  }

  static ({int colIndex, int consumedChars})? _parseColumnIdentifier(
    String input,
    int start,
    List<String> lowerColumns,
  ) {
    var i = start;
    while (i < input.length && input[i].trim().isEmpty) {
      i++;
    }
    if (i >= input.length) return null;

    if (input[i] == '"' || input[i] == '`') {
      final quote = input[i];
      i++;
      final buffer = StringBuffer();
      while (i < input.length) {
        if (input[i] == '\\' && i + 1 < input.length) {
          buffer.write(input[i + 1]);
          i += 2;
        } else if (input[i] == quote) {
          if (i + 1 < input.length && input[i + 1] == quote) {
            buffer.write(quote);
            i += 2;
          } else {
            i++;
            break;
          }
        } else {
          buffer.write(input[i]);
          i++;
        }
      }
      final rawName = buffer.toString();
      final colIdx = lowerColumns.indexOf(rawName.toLowerCase());
      if (colIdx != -1) {
        return (colIndex: colIdx, consumedChars: i - start);
      }
      return null;
    }

    // Unquoted column: [a-zA-Z_]\w*
    final rem = input.substring(i);
    final match = RegExp(r'^[a-zA-Z_]\w*').firstMatch(rem);
    if (match != null) {
      final name = match.group(0)!;
      final colIdx = lowerColumns.indexOf(name.toLowerCase());
      if (colIdx != -1) {
        return (colIndex: colIdx, consumedChars: (i - start) + name.length);
      }
    }

    return null;
  }

  static ({String value, int consumedChars})? _parseValue(
    String input,
    int start,
  ) {
    var i = start;
    while (i < input.length && input[i].trim().isEmpty) {
      i++;
    }
    if (i >= input.length) return null;

    if (input[i] == '\'' || input[i] == '"') {
      final quote = input[i];
      i++;
      final buffer = StringBuffer();
      while (i < input.length) {
        if (input[i] == '\\' && i + 1 < input.length) {
          final next = input[i + 1];
          if (next == quote || next == '\\') {
            buffer.write(next);
          } else if (next == 'n') {
            buffer.write('\n');
          } else if (next == 't') {
            buffer.write('\t');
          } else {
            buffer.write('\\');
            buffer.write(next);
          }
          i += 2;
        } else if (input[i] == quote) {
          if (i + 1 < input.length && input[i + 1] == quote) {
            buffer.write(quote);
            i += 2;
          } else {
            i++; // closing quote
            break;
          }
        } else {
          buffer.write(input[i]);
          i++;
        }
      }
      return (value: buffer.toString(), consumedChars: i - start);
    }

    // Unquoted value: read until whitespace, closing paren, opening paren, or comma
    final valStart = i;
    while (i < input.length &&
        input[i].trim().isNotEmpty &&
        input[i] != ')' &&
        input[i] != '(' &&
        input[i] != ',') {
      i++;
    }
    final raw = input.substring(valStart, i);
    if (raw.isEmpty) return null;
    return (value: raw, consumedChars: i - start);
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
