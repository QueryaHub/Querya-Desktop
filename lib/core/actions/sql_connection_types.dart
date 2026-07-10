import 'package:querya_desktop/core/storage/local_db.dart';

const kSqlCapableConnectionTypes = {'postgresql', 'mysql', 'sqlite'};

bool isSqlCapableConnection(ConnectionRow? connection) =>
    connection != null && kSqlCapableConnectionTypes.contains(connection.type);
