import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/security/safe_zip_extractor.dart';

const _tightLimits = ZipDecodeLimits(
  maxCompressedBytes: 4096,
  maxTotalUncompressedBytes: 8192,
  maxEntryCount: 5,
  maxEntryUncompressedBytes: 4096,
  maxCompressionRatio: 10,
);

Archive _singleFileArchive(String name, List<int> content) {
  return Archive()..addFile(ArchiveFile(name, content.length, content));
}

Future<File> _writeZip(Directory dir, Archive archive, String name) async {
  final bytes = ZipEncoder().encode(archive);
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(bytes);
  return file;
}

void main() {
  group('SafeZipExtractor', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('querya_safe_zip_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('decodes a small valid archive', () {
      final archive = _singleFileArchive('hello.txt', utf8.encode('hello'));
      final zipBytes = ZipEncoder().encode(archive);

      final decoded = SafeZipExtractor.decodeBytes(zipBytes, limits: _tightLimits);
      expect(decoded.length, 1);
      expect(decoded.first.name, 'hello.txt');
    });

    test('rejects archives exceeding max compressed bytes', () async {
      final file = File(p.join(tempDir.path, 'oversize.zip'));
      await file.writeAsBytes(List<int>.filled(5000, 1));

      expect(
        () => SafeZipExtractor.readBoundedBytes(file, limits: _tightLimits),
        throwsA(isA<SafeZipException>().having(
          (e) => e.message,
          'message',
          contains('maximum compressed size'),
        )),
      );
    });

    test('rejects archives with too many entries', () {
      final archive = Archive();
      for (var i = 0; i < 6; i++) {
        archive.addFile(ArchiveFile('file$i.txt', 1, [i]));
      }
      final zipBytes = ZipEncoder().encode(archive);

      expect(
        () => SafeZipExtractor.decodeBytes(zipBytes, limits: _tightLimits),
        throwsA(isA<SafeZipException>().having(
          (e) => e.message,
          'message',
          contains('too many entries'),
        )),
      );
    });

    test('rejects archives exceeding total uncompressed size', () {
      const limits = ZipDecodeLimits(
        maxCompressedBytes: 4096,
        maxTotalUncompressedBytes: 6000,
        maxEntryCount: 5,
        maxEntryUncompressedBytes: 5000,
        maxCompressionRatio: 100,
      );
      final archive = Archive()
        ..addFile(ArchiveFile('a.bin', 4000, List<int>.filled(4000, 1)))
        ..addFile(ArchiveFile('b.bin', 4000, List<int>.filled(4000, 2)));
      final zipBytes = ZipEncoder().encode(archive);

      expect(
        () => SafeZipExtractor.decodeBytes(zipBytes, limits: limits),
        throwsA(isA<SafeZipException>().having(
          (e) => e.message,
          'message',
          contains('total uncompressed size'),
        )),
      );
    });

    test('rejects high compression ratio zip bombs', () {
      const limits = ZipDecodeLimits(
        maxCompressedBytes: 4096,
        maxTotalUncompressedBytes: 8192,
        maxEntryCount: 5,
        maxEntryUncompressedBytes: 10000,
        maxCompressionRatio: 10,
      );
      final payload = List<int>.filled(5000, 0);
      final archive = _singleFileArchive('bomb.bin', payload);
      final zipBytes = ZipEncoder().encode(archive);

      expect(
        () => SafeZipExtractor.decodeBytes(zipBytes, limits: limits),
        throwsA(isA<SafeZipException>().having(
          (e) => e.message,
          'message',
          contains('compression ratio'),
        )),
      );
    });

    test('readAndDecodeFile reads bounded archives from disk', () async {
      final archive = _singleFileArchive('ok.txt', utf8.encode('ok'));
      final zipFile = await _writeZip(tempDir, archive, 'ok.zip');

      final decoded =
          await SafeZipExtractor.readAndDecodeFile(zipFile, limits: _tightLimits);
      expect(decoded.first.name, 'ok.txt');
    });

    test('ensureCompressedSizeAllowed rejects oversize before decode', () async {
      final file = File(p.join(tempDir.path, 'big.zip'));
      await file.writeAsBytes(List<int>.filled(5000, 1));

      expect(
        () => SafeZipExtractor.ensureCompressedSizeAllowed(
          file,
          limits: _tightLimits,
        ),
        throwsA(isA<SafeZipException>()),
      );
    });
  });
}
