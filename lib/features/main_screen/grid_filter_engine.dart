/// Client-side filter engine for Data Grid.
///
/// Evaluates complex multi-clause expressions with AND / OR / NOT, parentheses,
/// column predicates (`col = val`, `col > 10`), and free-text substring search.
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
  });

  final int colIndex;
  final String op;
  final String targetValue;

  @override
  bool evaluate(List<String> row, List<String> lowerColumns) {
    if (colIndex < 0 || colIndex >= row.length) return false;
    final cellValue = row[colIndex];
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
          while (i < input.length && input[i] != quote) {
            if (input[i] == '\\' && i + 1 < input.length) {
              i += 2;
            } else {
              i++;
            }
          }
          if (i < input.length) i++; // consume closing quote
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
      // or "status", "=", "'ACTIVE'"
      final colIdx = lowerColumns.indexOf(word.toLowerCase());
      if (colIdx != -1) {
        // Peek ahead for operator and value
        final remaining = input.substring(i).trimLeft();
        final opMatch = RegExp(r'^(>=|<=|!=|<>|==|=|>|<|:)\s*([^\s()]+)')
            .firstMatch(remaining);
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

      // Strip quotes from free text if present
      word = _stripQuotes(word);
      tokens.add(_FilterToken(_TokenType.text, value: word));
    }

    return tokens;
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
        return s.substring(1, s.length - 1).replaceAll(r"\'", "'").replaceAll(r'\"', '"');
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
    // Two terms or predicates in a row without explicit OR are treated as implicit AND
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
