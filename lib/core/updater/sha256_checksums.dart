import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Parses `sha256sum`-style manifest lines: `<hex>  <filename>`.
Map<String, String> parseSha256SumsText(String text) {
  final out = <String, String>{};
  for (final rawLine in const LineSplitter().convert(text)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;

    final hash = parts.first.toLowerCase();
    if (hash.length != 64 || !RegExp(r'^[0-9a-f]+$').hasMatch(hash)) {
      continue;
    }

    final fileName = parts.sublist(1).join(' ');
    out[fileName] = hash;
  }
  return out;
}

Future<String> sha256HexOfFile(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

/// Throws [UpdateChecksumMismatchException] when [expectedHex] does not match.
Future<void> verifyFileSha256({
  required File file,
  required String expectedHex,
}) async {
  final actual = await sha256HexOfFile(file);
  final expected = expectedHex.toLowerCase();
  if (actual != expected) {
    throw UpdateChecksumMismatchException(
      fileName: file.path.split(Platform.pathSeparator).last,
      expected: expected,
      actual: actual,
    );
  }
}

class UpdateChecksumMismatchException implements Exception {
  const UpdateChecksumMismatchException({
    required this.fileName,
    required this.expected,
    required this.actual,
  });

  final String fileName;
  final String expected;
  final String actual;

  @override
  String toString() =>
      'UpdateChecksumMismatchException: SHA256 mismatch for $fileName '
      '(expected $expected, got $actual)';
}
