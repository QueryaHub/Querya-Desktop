import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

const kSqlCapableConnectionTypes = {'postgresql', 'mysql', 'sqlite'};

bool isSqlCapableConnection(ConnectionRow? connection) {
  if (connection == null) return false;
  if (kSqlCapableConnectionTypes.contains(connection.type)) return true;
  return ExtensionDriverCatalog.isExtensionDriverConnection(connection);
}
