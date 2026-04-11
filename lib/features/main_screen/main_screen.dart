import 'dart:math' as math;

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart' as material show Scaffold, Container, MainAxisSize, GestureDetector, MouseRegion, SystemMouseCursors, HitTestBehavior, Icons, Icon;
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:querya_desktop/features/mysql/mysql_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/features/connections/driver_manager_dialog.dart';
import 'package:querya_desktop/features/connections/new_connection_dialog.dart';
import 'workspace_panel.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const double _minLeftWidth = 180;
  static const double _maxLeftWidth = 500;
  /// Minimum width reserved for workspace (avoid Row overflow when window is narrow).
  static const double _minWorkspaceWidth = 64;
  static const double _resizeHandleWidth = 6;
  double _leftPanelWidth = 260;

  /// Currently selected connection (null = no connection selected).
  ConnectionRow? _activeConnection;

  /// Currently selected Redis database (null = show stats).
  int? _activeRedisDb;

  /// Currently selected MongoDB database (null = show stats).
  String? _activeMongoDB;

  /// When set, user selected a PostgreSQL object in the tree.
  ({String database, String schema, String name, PostgresObjectKind kind})?
      _selectedPostgresObject;

  /// Bumped to tell [PostgresWorkspaceHome] to switch to the SQL tab.
  int _postgresSqlTabRequestToken = 0;

  /// When set, user selected a MySQL table or view in the tree.
  ({String database, String name, MysqlObjectKind kind})? _selectedMysqlObject;

  /// Bumped to tell [MysqlWorkspaceHome] to switch to the SQL tab.
  int _mysqlSqlTabRequestToken = 0;

  void _onConnectionSelected(ConnectionRow connection) {
    setState(() {
      _activeConnection = connection;
      _activeRedisDb = null;
      _activeMongoDB = null;
      _selectedPostgresObject = null;
      _selectedMysqlObject = null;
    });
  }

  void _onPostgresObjectSelected(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  ) {
    setState(() {
      _activeConnection = connection;
      _activeRedisDb = null;
      _activeMongoDB = null;
      _selectedMysqlObject = null;
      _selectedPostgresObject = (
        database: database,
        schema: schema,
        name: name,
        kind: kind,
      );
    });
  }

  void _onMysqlObjectSelected(
    ConnectionRow connection,
    String database,
    String name,
    MysqlObjectKind kind,
  ) {
    setState(() {
      _activeConnection = connection;
      _activeRedisDb = null;
      _activeMongoDB = null;
      _selectedPostgresObject = null;
      _selectedMysqlObject = (
        database: database,
        name: name,
        kind: kind,
      );
    });
  }

  void _onRedisDatabaseSelected(ConnectionRow connection, int database) {
    setState(() {
      _activeConnection = connection;
      _activeRedisDb = database;
      _activeMongoDB = null;
      _selectedPostgresObject = null;
      _selectedMysqlObject = null;
    });
  }

  void _onMongoDBDatabaseSelected(ConnectionRow connection, String database) {
    setState(() {
      _activeConnection = connection;
      _activeRedisDb = null;
      _activeMongoDB = database;
      _selectedPostgresObject = null;
      _selectedMysqlObject = null;
    });
  }

  void _onPostgresOpenSqlWorkspace(ConnectionRow connection) {
    setState(() {
      _activeConnection = connection;
      _activeRedisDb = null;
      _activeMongoDB = null;
      _selectedPostgresObject = null;
      _selectedMysqlObject = null;
      _postgresSqlTabRequestToken++;
    });
  }

  void _onMysqlOpenSqlWorkspace(ConnectionRow connection) {
    setState(() {
      _activeConnection = connection;
      _activeRedisDb = null;
      _activeMongoDB = null;
      _selectedPostgresObject = null;
      _selectedMysqlObject = null;
      _mysqlSqlTabRequestToken++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.dark.colorScheme;
    return material.Scaffold(
      backgroundColor: theme.background,
      body: Theme(
        data: AppTheme.dark,
        child: WindowBorder(
          color: theme.border.withValues(alpha: 0.6),
          width: 1,
          child: Column(
            children: [
              _CustomTitleBar(theme: theme),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxLeft = constraints.maxWidth -
                        _resizeHandleWidth -
                        _minWorkspaceWidth;
                    double leftW;
                    if (maxLeft <= 0) {
                      leftW = 0;
                    } else if (maxLeft < _minLeftWidth) {
                      leftW = maxLeft;
                    } else {
                      leftW = _leftPanelWidth.clamp(
                        _minLeftWidth,
                        math.min(_maxLeftWidth, maxLeft),
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(
                          width: leftW,
                          child: ConnectionsPanel(
                            onConnectionSelected: _onConnectionSelected,
                            onRedisDatabaseSelected: _onRedisDatabaseSelected,
                            onMongoDBDatabaseSelected: _onMongoDBDatabaseSelected,
                            onPostgresObjectSelected: _onPostgresObjectSelected,
                            onPostgresOpenSqlWorkspace: _onPostgresOpenSqlWorkspace,
                            onMysqlObjectSelected: _onMysqlObjectSelected,
                            onMysqlOpenSqlWorkspace: _onMysqlOpenSqlWorkspace,
                          ),
                        ),
                        _VerticalResizeHandle(
                          onDrag: (dx) {
                            setState(() {
                              final w = MediaQuery.sizeOf(context).width;
                              final ml = w -
                                  _resizeHandleWidth -
                                  _minWorkspaceWidth;
                              if (ml <= 0) return;
                              final next = _leftPanelWidth + dx;
                              if (ml < _minLeftWidth) {
                                _leftPanelWidth = next.clamp(0, ml);
                              } else {
                                _leftPanelWidth = next.clamp(
                                  _minLeftWidth,
                                  math.min(_maxLeftWidth, ml),
                                );
                              }
                            });
                          },
                        ),
                        Expanded(
                          child: WorkspacePanel(
                            activeConnection: _activeConnection,
                            selectedRedisDb: _activeRedisDb,
                            selectedMongoDb: _activeMongoDB,
                            selectedPostgresObject: _selectedPostgresObject,
                            postgresSqlTabRequestToken: _postgresSqlTabRequestToken,
                            selectedMysqlObject: _selectedMysqlObject,
                            mysqlSqlTabRequestToken: _mysqlSqlTabRequestToken,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerticalResizeHandle extends StatelessWidget {
  const _VerticalResizeHandle({required this.onDrag});

  final void Function(double dx) onDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    return material.MouseRegion(
      cursor: material.SystemMouseCursors.resizeColumn,
      child: material.GestureDetector(
        behavior: material.HitTestBehavior.opaque,
        onHorizontalDragUpdate: (e) => onDrag(e.delta.dx),
        child: material.Container(
          width: 6,
          color: theme.border.withValues(alpha: 0.15),
        ),
      ),
    );
  }
}

class _CustomTitleBar extends StatefulWidget {
  const _CustomTitleBar({required this.theme});

  final ColorScheme theme;

  @override
  State<_CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<_CustomTitleBar> {
  @override
  Widget build(BuildContext context) {
    final c = widget.theme;
    final buttonColors = WindowButtonColors(
      iconNormal: c.mutedForeground,
      mouseOver: c.muted.withValues(alpha: 0.5),
      mouseDown: c.muted.withValues(alpha: 0.7),
      iconMouseOver: c.foreground,
      iconMouseDown: c.foreground,
    );
    final closeButtonColors = WindowButtonColors(
      iconNormal: c.mutedForeground,
      mouseOver: const Color(0xFFE53935),
      mouseDown: const Color(0xFFB71C1C),
      iconMouseOver: const Color(0xFFFFFFFF),
      iconMouseDown: const Color(0xFFFFFFFF),
    );

    return material.Container(
      height: 40,
      color: c.background,
      child: WindowTitleBarBox(
        child: Row(
          children: [
            Expanded(
              child: MoveWindow(
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    const Text('Querya').semiBold().small(),
                    const Gap(24),
                    Menubar(
                      border: false,
                      popoverOffset: const Offset(0, 8),
                      children: [
                        MenuButton(
                          subMenu: [
                            MenuButton(onPressed: (_) {}, child: const Text('New')),
                            MenuButton(onPressed: (_) {}, child: const Text('Open...')),
                            MenuButton(onPressed: (_) {}, child: const Text('Save')),
                            const MenuDivider(),
                            MenuButton(onPressed: (_) {}, child: const Text('Exit')),
                          ],
                          child: const Text('File'),
                        ),
                        MenuButton(
                          subMenu: [
                            MenuButton(
                              leading: const material.Icon(material.Icons.add_link_rounded, size: 18),
                              trailing: const Text('Shift+Ctrl+N').xSmall().muted(),
                              onPressed: (ctx) async {
                                final type = await showNewConnectionDialog(ctx);
                                if (type != null) {
                                  // TODO: add connection (no folder)
                                }
                              },
                              child: const Text('New Database Connection'),
                            ),
                            MenuButton(
                              leading: const material.Icon(material.Icons.link_rounded, size: 18),
                              onPressed: (_) {},
                              child: const Text('New Connection from URL'),
                            ),
                            MenuButton(
                              leading: const material.Icon(material.Icons.settings_rounded, size: 18),
                              onPressed: (ctx) => showDriverManagerDialog(ctx),
                              child: const Text('Driver Manager'),
                            ),
                            const MenuDivider(),
                            MenuButton(
                              enabled: false,
                              leading: const material.Icon(material.Icons.power_rounded, size: 18),
                              onPressed: (_) {},
                              child: const Text('Connect'),
                            ),
                            MenuButton(
                              leading: const material.Icon(material.Icons.refresh_rounded, size: 18),
                              onPressed: (_) {},
                              child: const Text('Invalidate/Reconnect'),
                            ),
                            MenuButton(
                              leading: const material.Icon(material.Icons.power_off_rounded, size: 18),
                              onPressed: (_) {},
                              child: const Text('Disconnect'),
                            ),
                            MenuButton(onPressed: (_) {}, child: const Text('Disconnect All')),
                            MenuButton(onPressed: (_) {}, child: const Text('Disconnect Others')),
                            const MenuDivider(),
                            MenuButton(
                              leading: const material.Icon(material.Icons.lock_outline_rounded, size: 18),
                              onPressed: (_) {},
                              child: const Text('Read-only'),
                            ),
                          ],
                          child: const Text('Connection'),
                        ),
                        MenuButton(
                          subMenu: [
                            MenuButton(onPressed: (_) {}, child: const Text('About')),
                            MenuButton(onPressed: (_) {}, child: const Text('Documentation')),
                          ],
                          child: const Text('Help'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                MinimizeWindowButton(colors: buttonColors),
                MaximizeWindowButton(colors: buttonColors),
                CloseWindowButton(colors: closeButtonColors),
              ],
            )
          ],
        ),
      ),
    );
  }
}
