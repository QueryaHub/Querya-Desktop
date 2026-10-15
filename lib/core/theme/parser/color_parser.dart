import 'dart:ui';

/// Parses VS Code color strings into Flutter [Color].
///
/// Hex digits are read straight from the code units (no substring / `int.parse`
/// per channel), so loading a theme with thousands of rules allocates nothing
/// per color but the result.
Color parseVsCodeColor(String input) {
  final s = input.trim();
  if (s.isEmpty) {
    throw const FormatException('Empty color string');
  }
  final from = s.codeUnitAt(0) == 0x23 ? 1 : 0; // '#'
  try {
    switch (s.length - from) {
      case 3: // RGB
        return Color.fromARGB(
          0xFF,
          _nibble(s, from) * 17,
          _nibble(s, from + 1) * 17,
          _nibble(s, from + 2) * 17,
        );
      case 4: // RGBA
        return Color.fromARGB(
          _nibble(s, from + 3) * 17,
          _nibble(s, from) * 17,
          _nibble(s, from + 1) * 17,
          _nibble(s, from + 2) * 17,
        );
      case 6: // RRGGBB
        return Color.fromARGB(
          0xFF,
          _byte(s, from),
          _byte(s, from + 2),
          _byte(s, from + 4),
        );
      case 8: // RRGGBBAA
        return Color.fromARGB(
          _byte(s, from + 6),
          _byte(s, from),
          _byte(s, from + 2),
          _byte(s, from + 4),
        );
    }
  } on FormatException {
    throw FormatException('Unsupported color format: $input');
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
      return Color.fromARGB(
        _byte(s, 0),
        _byte(s, 2),
        _byte(s, 4),
        _byte(s, 6),
      );
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
  final withAlpha = color.a < 1.0;
  final units = List<int>.filled(withAlpha ? 9 : 7, 0x23); // '#'
  _writeHexByte(units, 1, _channel(color.r));
  _writeHexByte(units, 3, _channel(color.g));
  _writeHexByte(units, 5, _channel(color.b));
  if (withAlpha) _writeHexByte(units, 7, _channel(color.a));
  return String.fromCharCodes(units);
}

int _channel(double component) =>
    (component * 255.0).round().clamp(0, 255);

const String _hexChars = '0123456789abcdef';

void _writeHexByte(List<int> out, int at, int value) {
  out[at] = _hexChars.codeUnitAt(value >> 4);
  out[at + 1] = _hexChars.codeUnitAt(value & 0xF);
}

/// The hex digit at [at] in [s], or a [FormatException].
int _nibble(String s, int at) {
  final c = s.codeUnitAt(at);
  if (c >= 0x30 && c <= 0x39) return c - 0x30; // 0-9
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10; // a-f
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10; // A-F
  throw FormatException('Invalid hex digit', s, at);
}

/// Two hex digits at [at] as one byte.
int _byte(String s, int at) => (_nibble(s, at) << 4) | _nibble(s, at + 1);
