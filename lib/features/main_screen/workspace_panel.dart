import 'package:flutter/material.dart' as material
    show
        Align,
        Alignment,
        Container,
        EdgeInsets,
        Padding,
        Center,
        Icon,
        Icons,
        MainAxisSize,
        SizedBox,
        Widget,
        Column;
import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/motion/querya_switching_body.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import 'package:querya_desktop/features/mysql/mysql_object_kind.dart';
import 'package:querya_desktop/features/mysql/mysql_routine_view.dart';
import 'package:querya_desktop/features/mysql/mysql_table_view.dart';
import 'package:querya_desktop/features/mysql/mysql_workspace_home.dart';
import 'package:querya_desktop/features/mongodb/mongo_explorer_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_stats_view.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_workspace.dart';
import 'package:querya_desktop/features/postgresql/postgres_workspace_home.dart';
import 'package:querya_desktop/features/redis/redis_explorer_view.dart';
import 'package:querya_desktop/features/redis/redis_view.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart'
    show SqliteObjectKind;
import 'package:querya_desktop/features/extensions/extension_table_view.dart';
import 'package:querya_desktop/features/extensions/extension_workspace_home.dart';
import 'package:querya_desktop/features/sqlite/sqlite_table_view.dart';
import 'package:querya_desktop/features/sqlite/sqlite_workspace_home.dart';
import 'workspace_empty_hero.dart';

/// Main workspace for the currently selected connection.
class WorkspacePanel extends StatefulWidget {
  const WorkspacePanel({
    super.key,
    this.activeConnection,
    this.selectedRedisDb,
    this.selectedMongoDb,
    this.selectedPostgresObject,
    this.postgresSqlTabRequestToken = 0,
    this.postgresSqlEditorContext,
    this.postgresSqlEditorContextToken = 0,
    this.selectedMysqlObject,
    this.mysqlSqlTabRequestToken = 0,
    this.selectedSqliteObject,
    this.sqliteSqlTabRequestToken = 0,
    this.selectedExtensionObject,
    this.extensionSqlTabRequestToken = 0,
    this.isReadOnly = false,
    this.onRequestNewConnection,
    this.onRequestNewConnectionFromUrl,
    this.onRequestOpenSqlite,
    this.onOpenConnection,
  });

  /// Currently selected connection from the sidebar.
  final ConnectionRow? activeConnection;
  final bool isReadOnly;

  /// When set, the user selected a specific Redis database in the sidebar tree.
  /// null = show stats, non-null = show data explorer for that db.
  final int? selectedRedisDb;

  /// When set, the user selected a specific MongoDB database in the sidebar tree.
  /// null = show stats, non-null = show data explorer for that db.
  final String? selectedMongoDb;

  /// When set, the user selected a PostgreSQL object in the sidebar tree.
  /// null = show stats, non-null = show table/grid or definition view.
  final ({
    String database,
    String schema,
    String name,
    PostgresObjectKind kind
  })? selectedPostgresObject;

  /// Incremented by [MainScreen] to switch the PostgreSQL home view to the SQL tab.
  final int postgresSqlTabRequestToken;

  /// Seeds the SQL editor from the last table/view/matview tree selection.
  final ({
    String database,
    String schema,
    String name,
    PostgresObjectKind kind
  })? postgresSqlEditorContext;
  final int postgresSqlEditorContextToken;

  /// When set, the user selected a MySQL table or view in the sidebar tree.
  final ({
    String database,
    String name,
    MysqlObjectKind kind
  })? selectedMysqlObject;

  /// Incremented by [MainScreen] to switch the MySQL home view to the SQL tab.
  final int mysqlSqlTabRequestToken;

  /// When set, the user selected a SQLite table or view in the sidebar tree.
  final ({String name, SqliteObjectKind kind})? selectedSqliteObject;

  /// Incremented by [MainScreen] to switch the SQLite home view to the SQL tab.
  final int sqliteSqlTabRequestToken;

  /// When set, the user selected a table/view in an extension driver tree.
  final ({
    String database,
    String name,
  })? selectedExtensionObject;

  /// Incremented by [MainScreen] to switch the Extension home view to the SQL tab.
  final int extensionSqlTabRequestToken;

  /// Empty-state hero: primary CTA to add a connection.
  final void Function()? onRequestNewConnection;
  final void Function()? onRequestNewConnectionFromUrl;
  final void Function()? onRequestOpenSqlite;
  final void Function(ConnectionRow connection)? onOpenConnection;

  @override
  State<WorkspacePanel> createState() => _WorkspacePanelState();
}

class _WorkspacePanelState extends State<WorkspacePanel> {
  /// Keeps the last connected workspace mounted so empty↔active can cross-fade.
  material.Widget? _cachedActiveBody;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeConn = widget.activeConnection;

    final empty = material.Align(
      alignment: material.Alignment.topCenter,
      child: WorkspaceEmptyHero(
        onNewConnection: widget.onRequestNewConnection ?? () {},
        onNewConnectionFromUrl: widget.onRequestNewConnectionFromUrl,
        onOpenSqlite: widget.onRequestOpenSqlite,
        onOpenConnection: widget.onOpenConnection,
      ),
    );

    final material.Widget activeBody;
    if (activeConn == null) {
      activeBody = _cachedActiveBody ?? const material.SizedBox.expand();
    } else {
      activeBody = _buildActiveConnectionBody(theme, activeConn);
      _cachedActiveBody = activeBody;
    }

    return material.Container(
      color: theme.colorScheme.background,
      child: QueryaSwitchingBody(
        index: activeConn == null ? 0 : 1,
        children: [
          empty,
          material.SizedBox.expand(child: activeBody),
        ],
      ),
    );
  }

  material.Widget _buildActiveConnectionBody(
    ThemeData theme,
    ConnectionRow activeConn,
  ) {
    material.Widget? driverWorkspace;
    switch (activeConn.type) {
      case 'postgresql':
        final pg = widget.selectedPostgresObject;
        driverWorkspace = pg == null
            ? PostgresWorkspaceHome(
                key: ValueKey('pg_home_${activeConn.id}'),
                connectionRow: activeConn,
                postgresSqlEditorContext: widget.postgresSqlEditorContext,
                postgresSqlEditorContextToken:
                    widget.postgresSqlEditorContextToken,
                sqlTabRequestToken: widget.postgresSqlTabRequestToken,
                isReadOnly: widget.isReadOnly,
              )
            : buildPostgresObjectWorkspace(
                connection: activeConn,
                pg: pg,
              );
        break;
      case 'mysql':
        final my = widget.selectedMysqlObject;
        if (my == null) {
          driverWorkspace = MysqlWorkspaceHome(
            key: ValueKey('mysql_home_${activeConn.id}'),
            connectionRow: activeConn,
            sqlTabRequestToken: widget.mysqlSqlTabRequestToken,
            isReadOnly: widget.isReadOnly,
          );
        } else if (my.kind == MysqlObjectKind.procedure ||
            my.kind == MysqlObjectKind.function) {
          driverWorkspace = MysqlRoutineView(
            key: ValueKey(
              'mysql_${activeConn.id}_${my.database}_${my.name}_${my.kind}',
            ),
            connectionRow: activeConn,
            database: my.database,
            routineName: my.name,
            isFunction: my.kind == MysqlObjectKind.function,
          );
        } else {
          driverWorkspace = MysqlTableView(
            key: ValueKey(
              'mysql_${activeConn.id}_${my.database}_${my.name}_${my.kind}',
            ),
            connectionRow: activeConn,
            database: my.database,
            tableName: my.name,
            isView: my.kind == MysqlObjectKind.view,
          );
        }
        break;
      case 'mongodb':
        final mongoDb = widget.selectedMongoDb;
        driverWorkspace = mongoDb != null
            ? MongoExplorerView(
                key: ValueKey('mongo_${activeConn.id}_db_$mongoDb'),
                connectionRow: activeConn,
                database: mongoDb,
              )
            : MongoStatsView(
                key: ValueKey(activeConn.id),
                connectionRow: activeConn,
              );
        break;
      case 'redis':
        final redisDb = widget.selectedRedisDb;
        driverWorkspace = redisDb != null
            ? RedisExplorerView(
                key: ValueKey('redis_${activeConn.id}_db_$redisDb'),
                connectionRow: activeConn,
                database: redisDb,
              )
            : RedisView(
                key: ValueKey(activeConn.id),
                connectionRow: activeConn,
              );
        break;
      case 'sqlite':
        final sq = widget.selectedSqliteObject;
        driverWorkspace = sq == null
            ? SqliteWorkspaceHome(
                key: ValueKey('sqlite_home_${activeConn.id}'),
                connectionRow: activeConn,
                sqlTabRequestToken: widget.sqliteSqlTabRequestToken,
                isReadOnly: widget.isReadOnly,
              )
            : SqliteTableView(
                key: ValueKey(
                  'sqlite_${activeConn.id}_${sq.name}_${sq.kind}',
                ),
                connectionRow: activeConn,
                tableName: sq.name,
                isView: sq.kind == SqliteObjectKind.view,
              );
        break;
      default:
        if (ExtensionDriverCatalog.isExtensionDriverConnection(activeConn)) {
          final obj = widget.selectedExtensionObject;
          driverWorkspace = obj == null
              ? ExtensionWorkspaceHome(
                  key: ValueKey('ext_home_${activeConn.id}'),
                  connectionRow: activeConn,
                  sqlTabRequestToken: widget.extensionSqlTabRequestToken,
                  isReadOnly: widget.isReadOnly,
                )
              : ExtensionTableView(
                  key: ValueKey(
                    'ext_table_${activeConn.id}_${obj.database}_${obj.name}',
                  ),
                  connectionRow: activeConn,
                  database: obj.database,
                  tableName: obj.name,
                );
        }
        break;
    }

    if (driverWorkspace != null) {
      return driverWorkspace;
    }

    return material.Center(
      child: material.Padding(
        padding: const material.EdgeInsets.all(32),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Icon(
              material.Icons.error_outline_rounded,
              size: 36,
              color: theme.colorScheme.mutedForeground,
            ),
            const material.SizedBox(height: 12),
            const Text('Unsupported connection type').semiBold(),
            const material.SizedBox(height: 6),
            Text(
              'No workspace is registered for “${activeConn.type}”.',
            ).muted().small(),
          ],
        ),
      ),
    );
  }
}
