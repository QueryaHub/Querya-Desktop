import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'driver_urls.dart';

export 'driver_urls.dart' show DownloadableDriver;

/// Manages downloaded database driver files (e.g. PostgreSQL JDBC JAR).
/// Drivers are stored under [applicationSupport]/querya_desktop/drivers/.
class DriverStorage {
  DriverStorage._();
  static final DriverStorage instance = DriverStorage._();

  Directory? _driversDir;

  Future<Directory> _getDriversDir() async {
    if (_driversDir != null) return _driversDir!;
    final appSupport = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appSupport.path, 'querya_desktop', 'drivers'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _driversDir = dir;
    return dir;
  }

  /// Path to the driver JAR file for [driver] (whether it exists or not).
  Future<String> getJarPath(DownloadableDriver driver) async {
    final dir = await _getDriversDir();
    return p.join(dir.path, driver.jarFileName);
  }

  /// Whether the driver JAR for [driver] is present on disk.
  Future<bool> isInstalled(DownloadableDriver driver) async {
    final path = await getJarPath(driver);
    return File(path).exists();
  }

  /// Downloads the driver for [driver] from the official URL.
  /// Overwrites existing file if present.
  Future<void> download(
    DownloadableDriver driver, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await _getDriversDir();
    final filePath = p.join(dir.path, driver.jarFileName);
    final file = File(filePath);

    final response = await http.get(Uri.parse(driver.url));
    if (response.statusCode != 200) {
      throw DriverDownloadException(
        'Failed to download ${driver.name} driver: HTTP ${response.statusCode}',
      );
    }
    await file.writeAsBytes(response.bodyBytes);
    onProgress?.call(response.bodyBytes.length, response.bodyBytes.length);
  }

  /// Deletes the downloaded driver JAR for [driver].
  Future<void> delete(DownloadableDriver driver) async {
    final path = await getJarPath(driver);
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  // --- Legacy PostgreSQL-only API (delegate to generic) ---

  Future<String> getPostgresqlJarPath() => getJarPath(DownloadableDriver.postgresql);
  Future<bool> isPostgresqlInstalled() => isInstalled(DownloadableDriver.postgresql);
  Future<void> downloadPostgresql({void Function(int received, int total)? onProgress}) =>
      download(DownloadableDriver.postgresql, onProgress: onProgress);
  Future<void> deletePostgresql() => delete(DownloadableDriver.postgresql);
}

class DriverDownloadException implements Exception {
  DriverDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}
