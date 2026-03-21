// Rows for PostgreSQL browser metadata (indexes, triggers, types, etc.).

class PgIndexRow {
  const PgIndexRow({
    required this.tableName,
    required this.indexName,
    required this.indexDef,
    this.sizeBytes,
  });

  final String tableName;
  final String indexName;
  final String indexDef;
  final int? sizeBytes;
}

class PgTriggerRow {
  const PgTriggerRow({
    required this.tableName,
    required this.triggerName,
    required this.definition,
  });

  final String tableName;
  final String triggerName;
  final String definition;
}

class PgTypeRow {
  const PgTypeRow({
    required this.name,
    required this.kind,
  });

  final String name;
  final String kind;
}

class PgExtensionRow {
  const PgExtensionRow({
    required this.name,
    required this.version,
  });

  final String name;
  final String version;
}

class PgFdwRow {
  const PgFdwRow({
    required this.name,
    this.handler,
  });

  final String name;
  final String? handler;
}

class PgForeignServerRow {
  const PgForeignServerRow({
    required this.serverName,
    required this.fdwName,
  });

  final String serverName;
  final String fdwName;
}

class PgTablePrivilegeRow {
  const PgTablePrivilegeRow({
    required this.grantee,
    required this.privilegeType,
    required this.isGrantable,
  });

  final String grantee;
  final String privilegeType;
  final String isGrantable;
}
