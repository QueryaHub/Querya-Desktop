/// Official download URLs and file names for database drivers.
/// Used by [DriverStorage] for download/install.
/// Redis and MongoDB use Dart packages (built-in); only JAR-based drivers are listed here.

/// PostgreSQL JDBC driver (official jdbc.postgresql.org).
const postgresqlDriverUrl = 'https://jdbc.postgresql.org/download/postgresql-42.7.10.jar';

/// Local file name for the PostgreSQL driver JAR.
const postgresqlJarFileName = 'postgresql-42.7.10.jar';

/// Identifies a driver that can be downloaded and uninstalled (JAR).
enum DownloadableDriver {
  postgresql,
}

extension DownloadableDriverUrls on DownloadableDriver {
  String get url => switch (this) {
        DownloadableDriver.postgresql => postgresqlDriverUrl,
      };
  String get jarFileName => switch (this) {
        DownloadableDriver.postgresql => postgresqlJarFileName,
      };
}
