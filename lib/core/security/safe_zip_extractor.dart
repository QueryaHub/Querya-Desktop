import 'dart:io';

import 'package:archive/archive.dart';

/// Bounds for zip decode/extract to mitigate zip bombs and memory exhaustion.
class ZipDecodeLimits {
  const ZipDecodeLimits({
    required this.maxCompressedBytes,
    required this.maxTotalUncompressedBytes,
    required this.maxEntryCount,
    required this.maxEntryUncompressedBytes,
    required this.maxCompressionRatio,
  });

  final int maxCompressedBytes;
  final int maxTotalUncompressedBytes;
  final int maxEntryCount;
  final int maxEntryUncompressedBytes;
  final double maxCompressionRatio;

  /// Default limits for marketplace, sideload, and updater archives.
  static const ZipDecodeLimits standard = ZipDecodeLimits(
    maxCompressedBytes: 100 * 1024 * 1024,
    maxTotalUncompressedBytes: 500 * 1024 * 1024,
    maxEntryCount: 10000,
    maxEntryUncompressedBytes: 100 * 1024 * 1024,
    maxCompressionRatio: 100,
  );
}

/// Thrown when an archive exceeds [ZipDecodeLimits].
class SafeZipException implements Exception {
  SafeZipException(this.message);

  final String message;

  @override
  String toString() => 'SafeZipException: $message';
}

/// Bounded zip decode used by marketplace, sideload, and updater paths.
abstract final class SafeZipExtractor {
  /// Ensures [file] is within [limits.maxCompressedBytes] before reading.
  static Future<int> ensureCompressedSizeAllowed(
    File file, {
    ZipDecodeLimits limits = ZipDecodeLimits.standard,
  }) async {
    final length = await file.length();
    if (length > limits.maxCompressedBytes) {
      throw SafeZipException(
        'Archive exceeds maximum compressed size '
        '(${limits.maxCompressedBytes} bytes).',
      );
    }
    return length;
  }

  /// Reads the whole file into memory after size check.
  ///
  /// Prefer [readAndDecodeFile] (file-stream decode) when you only need an
  /// [Archive], so compressed bytes are not held as a separate [List].
  static Future<List<int>> readBoundedBytes(
    File file, {
    ZipDecodeLimits limits = ZipDecodeLimits.standard,
  }) async {
    await ensureCompressedSizeAllowed(file, limits: limits);
    return file.readAsBytes();
  }

  static Archive decodeBytes(
    List<int> bytes, {
    ZipDecodeLimits limits = ZipDecodeLimits.standard,
  }) {
    if (bytes.length > limits.maxCompressedBytes) {
      throw SafeZipException(
        'Archive exceeds maximum compressed size '
        '(${limits.maxCompressedBytes} bytes).',
      );
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (error) {
      throw SafeZipException('Failed to decode zip archive: $error');
    }

    _validateArchive(
      archive,
      compressedBytes: bytes.length,
      limits: limits,
    );
    return archive;
  }

  /// Decodes [file] via [InputFileStream] (buffered file reads) instead of
  /// materializing the full compressed payload as a [List] first.
  static Future<Archive> readAndDecodeFile(
    File file, {
    ZipDecodeLimits limits = ZipDecodeLimits.standard,
  }) async {
    final compressedBytes =
        await ensureCompressedSizeAllowed(file, limits: limits);

    final input = InputFileStream(file.path);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(input);
      } on Object catch (error) {
        throw SafeZipException('Failed to decode zip archive: $error');
      }

      _validateArchive(
        archive,
        compressedBytes: compressedBytes,
        limits: limits,
      );
      return archive;
    } finally {
      await input.close();
    }
  }

  static void _validateArchive(
    Archive archive, {
    required int compressedBytes,
    required ZipDecodeLimits limits,
  }) {
    if (archive.length > limits.maxEntryCount) {
      throw SafeZipException(
        'Archive contains too many entries (${archive.length}; '
        'max ${limits.maxEntryCount}).',
      );
    }

    var totalUncompressed = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;

      final size = entry.size;
      if (size > limits.maxEntryUncompressedBytes) {
        throw SafeZipException(
          'Archive entry "${entry.name}" exceeds maximum uncompressed size '
          '($size bytes; max ${limits.maxEntryUncompressedBytes}).',
        );
      }

      totalUncompressed += size;
      if (totalUncompressed > limits.maxTotalUncompressedBytes) {
        throw SafeZipException(
          'Archive exceeds maximum total uncompressed size '
          '(max ${limits.maxTotalUncompressedBytes} bytes).',
        );
      }
    }

    if (compressedBytes > 0 && totalUncompressed > 0) {
      final ratio = totalUncompressed / compressedBytes;
      if (ratio > limits.maxCompressionRatio) {
        throw SafeZipException(
          'Archive compression ratio is too high '
          '(${ratio.toStringAsFixed(1)}:1; max ${limits.maxCompressionRatio}:1).',
        );
      }
    }
  }
}
