import 'dart:ui';

/// Parses VS Code color strings into Flutter [Color].
Color parseVsCodeColor(String input) {
  var s = input.trim();
  if (s.isEmpty) {
    throw const FormatException('Empty color string');
  }
  if (s.startsWith('#')) {
    s = s.substring(1);
  }
  if (s.length == 3) {
    final r = s[0];
    final g = s[1];
    final b = s[2];
    s = '$r$r$g$g$b$b';
    return Color(int.parse('FF$s', radix: 16));
  }
  if (s.length == 4) {
    final r = s[0];
    final g = s[1];
    final b = s[2];
    final a = s[3];
    s = '$r$r$g$g$b$b$a$a';
    return _fromRgbaHex(s);
  }
  if (s.length == 6) {
    return Color(int.parse('FF$s', radix: 16));
  }
  if (s.length == 8) {
    return _fromRgbaHex(s);
  }
  throw FormatException('Unsupported color format: $input');
}

/// Parses Querya custom theme hex strings into Flutter [Color].
///
/// Accepts `#RRGGBB`, `RRGGBB`, `#AARRGGBB`, and `AARRGGBB`. Shorthand `#RGB` /
/// `#RGBA` and 6-digit values delegate to [parseVsCodeColor]. Eight-digit values
/// use alpha-first `AARRGGBB` (Querya custom), not VS Code `RRGGBBAA`.
Color parseQueryaThemeColor(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw FormatException('Invalid Querya theme color: $raw');
  }

  var s = trimmed;
  if (s.startsWith('#')) {
    s = s.substring(1);
  }

  if (s.length == 8) {
    try {
      final aa = int.parse(s.substring(0, 2), radix: 16);
      final rr = int.parse(s.substring(2, 4), radix: 16);
      final gg = int.parse(s.substring(4, 6), radix: 16);
      final bb = int.parse(s.substring(6, 8), radix: 16);
      return Color.fromARGB(aa, rr, gg, bb);
    } on FormatException {
      throw FormatException('Invalid Querya theme color: $raw');
    }
  }

  try {
    return parseVsCodeColor(trimmed.startsWith('#') ? trimmed : '#$s');
  } on FormatException {
    throw FormatException('Invalid Querya theme color: $raw');
  }
}

/// Encodes a [Color] as a VS Code hex string (`#RRGGBB` or `#RRGGBBAA`).
String formatVsCodeColor(Color color) {
  String channel(double component) =>
      (component * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final rr = channel(color.r);
  final gg = channel(color.g);
  final bb = channel(color.b);
  if (color.a < 1.0) {
    final aa = channel(color.a);
    return '#$rr$gg$bb$aa';
  }
  return '#$rr$gg$bb';
}

Color _fromRgbaHex(String eight) {
  final rr = eight.substring(0, 2);
  final gg = eight.substring(2, 4);
  final bb = eight.substring(4, 6);
  final aa = eight.substring(6, 8);
  return Color.fromARGB(
    int.parse(aa, radix: 16),
    int.parse(rr, radix: 16),
    int.parse(gg, radix: 16),
    int.parse(bb, radix: 16),
  );
}
