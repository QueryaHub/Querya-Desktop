/// Strips JSONC (comments, trailing commas) to valid JSON for [dart:convert].
String stripJsonc(String input) {
  final out = StringBuffer();
  var i = 0;
  final len = input.length;

  while (i < len) {
    final ch = input[i];
    final next = i + 1 < len ? input[i + 1] : '';

    if (ch == '"') {
      out.write(_copyStringLiteral(input, i));
      i = _skipStringLiteral(input, i);
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

String _copyStringLiteral(String s, int start) {
  final buf = StringBuffer();
  var i = start;
  buf.write(s[i]);
  i++;
  while (i < s.length) {
    final ch = s[i];
    buf.write(ch);
    if (ch == '\\' && i + 1 < s.length) {
      i++;
      buf.write(s[i]);
    } else if (ch == '"') {
      i++;
      break;
    }
    i++;
  }
  return buf.toString();
}

int _skipStringLiteral(String s, int start) {
  var i = start + 1;
  while (i < s.length) {
    if (s[i] == '\\') {
      i += 2;
      continue;
    }
    if (s[i] == '"') {
      return i + 1;
    }
    i++;
  }
  return s.length;
}
