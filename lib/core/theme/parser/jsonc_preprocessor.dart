/// Strips JSONC (comments, trailing commas) to valid JSON for [dart:convert].
String stripJsonc(String input) {
  final out = StringBuffer();
  var i = 0;
  final len = input.length;

  while (i < len) {
    final ch = input[i];
    final next = i + 1 < len ? input[i + 1] : '';

    if (ch == '"') {
      // One scan finds the closing quote; the literal is copied as a slice.
      final end = _stringLiteralEnd(input, i);
      out.write(input.substring(i, end));
      i = end;
      continue;
    }

    if (ch == '/' && next == '/') {
      i += 2;
      while (i < len && input[i] != '\n') {
        i++;
      }
      continue;
    }

    if (ch == '/' && next == '*') {
      i += 2;
      while (i < len) {
        if (input[i] == '*' && i + 1 < len && input[i + 1] == '/') {
          i += 2;
          break;
        }
        i++;
      }
      continue;
    }

    if (ch == ',') {
      var j = i + 1;
      while (j < len && _isWhitespace(input[j])) {
        j++;
      }
      if (j < len && (input[j] == '}' || input[j] == ']')) {
        i++;
        continue;
      }
    }

    out.write(ch);
    i++;
  }

  return out.toString();
}

bool _isWhitespace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

/// Offset after the string literal that opens at [start] (a `"`): past its
/// closing quote, or the end of [s] when it is not terminated. A backslash
/// escapes the next character.
int _stringLiteralEnd(String s, int start) {
  final len = s.length;
  var i = start + 1;
  while (i < len) {
    final c = s.codeUnitAt(i);
    if (c == 0x5C) {
      i += 2;
      continue;
    }
    if (c == 0x22) return i + 1;
    i++;
  }
  return len;
}
