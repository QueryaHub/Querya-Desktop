import 'package:flutter/widgets.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/querya_split_handle.dart';
import 'package:querya_desktop/core/motion/querya_spring.dart';
import 'package:querya_desktop/core/motion/querya_spring_controller.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:querya_desktop/core/ui/querya_shell_status.dart';
import 'package:querya_desktop/features/main_screen/connections_panel_width_persist.dart';
import 'package:querya_desktop/features/mysql/mysql_object_kind.dart';
import 'package:querya_desktop/features/mysql/mysql_sql_tx_guard.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgres_sql_tx_guard.dart';
import 'package:querya_desktop/features/sqlite/sqlite_sql_tx_guard.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'main_screen_workspace_state.dart';
import 'workspace_panel.dart';

/// Owns splitter width and collapsible spring motion.
class MainContentSplit extends StatefulWidget {
  const MainContentSplit({
    super.key,
    required this.connectionsPanelKey,
    required this.workspace,
    required this.onConnectionSelected,
    required this.onPostgresObjectSelected,
    required this.onMysqlObjectSelected,
    required this.onSqliteObjectSelected,
    required this.onExtensionObjectSelected,
    required this.onRedisDatabaseSelected,
    required this.onMongoDBDatabaseSelected,
    required this.onMongoCollectionSelected,
    required this.onPostgresOpenSqlWorkspace,
    required this.onMysqlOpenSqlWorkspace,
    required this.onSqliteOpenSqlWorkspace,
    required this.onRequestNewConnection,
    required this.onRequestNewConnectionFromUrl,
    required this.onRequestOpenSqlite,
    this.onRequestLaunchDemo,
    this.onRequestOpenTour,
    required this.onOpenConnection,
    this.onSidebarVisibilityChanged,
    this.initialMongoCollection,
  });

  final GlobalKey<ConnectionsPanelState> connectionsPanelKey;
  final ValueNotifier<MainScreenWorkspaceState> workspace;
  final ValueChanged<bool>? onSidebarVisibilityChanged;
  final void Function(ConnectionRow) onConnectionSelected;
  final void Function(
    ConnectionRow,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  ) onPostgresObjectSelected;
  final void Function(
    ConnectionRow,
    String database,
    String name,
    MysqlObjectKind kind,
  ) onMysqlObjectSelected;
  final void Function(
    ConnectionRow,
    String name,
    SqliteObjectKind kind,
  ) onSqliteObjectSelected;
  final void Function(
    ConnectionRow,
    String database,
    String name,
  ) onExtensionObjectSelected;
  final void Function(ConnectionRow, int) onRedisDatabaseSelected;
  final void Function(ConnectionRow, String) onMongoDBDatabaseSelected;
  final void Function(ConnectionRow, String, String) onMongoCollectionSelected;
  final OnPostgresOpenSqlWorkspace onPostgresOpenSqlWorkspace;
  final void Function(ConnectionRow) onMysqlOpenSqlWorkspace;
  final void Function(ConnectionRow) onSqliteOpenSqlWorkspace;
  final VoidCallback onRequestNewConnection;
  final VoidCallback onRequestNewConnectionFromUrl;
  final VoidCallback onRequestOpenSqlite;
  final String? initialMongoCollection;
  final VoidCallback? onRequestLaunchDemo;
  final VoidCallback? onRequestOpenTour;
  final void Function(ConnectionRow) onOpenConnection;

  @override
  State<MainContentSplit> createState() => MainContentSplitState();
}

class MainContentSplitState extends State<MainContentSplit>
    with SingleTickerProviderStateMixin {
  static const double _minLeftWidth = 180;
  static const double _maxLeftWidth = 500;
  static const double _minWorkspaceWidth = 64;
  static const double _resizeHandleWidth = 6;
  static const double _collapseThreshold = 1.0;

  /// High-responsiveness critically damped spring for fluid sidebar toggling (~0.22s).
  static const SpringDescription _sidebarSpring = SpringDescription(
    mass: 1.0,
    stiffness: 580.0,
    damping: 48.0,
  );

  late final QueryaSpringController _widthSpring;
  late final ConnectionsPanelWidthPersist _widthPersist;
  VoidCallback? _persistWhenSettled;
  double _lastMaxWidth = 1200;
  double _lastExpandedWidth = kDefaultConnectionsPanelWidth;
  bool _sidebarVisible = true;

  @override
  void initState() {
    super.initState();
    _widthPersist = ConnectionsPanelWidthPersist(
      write: AppSettings.instance.setConnectionsPanelWidth,
    );
    _widthSpring = QueryaSpringController(
      vsync: this,
      value: kDefaultConnectionsPanelWidth,
      spring: _sidebarSpring,
      cubicDuration: QueryaMotion.sidebarCubic,
      cubicCurve: QueryaMotion.enter,
    );
    _widthSpring.addListener(_onWidthSpringChanged);
    unawaited(_restoreState());
  }

  Future<void> _restoreLastSelectedObject() async {
    final ws = widget.workspace.value;
    final conn = ws.activeConnection;
    final pg = ws.lastSelectedPostgresObject;
    if (conn != null && conn.type == 'postgresql' && pg != null) {
      if (!await confirmOpenPostgresTableIfSqlTx(
        context,
        connection: conn,
        database: pg.database,
        kind: pg.kind,
      )) {
        return;
      }
    }
    if (!mounted) return;
    final sq = ws.lastSelectedSqliteObject;
    if (conn != null && conn.type == 'sqlite' && sq != null) {
      if (!await confirmOpenSqliteTableIfSqlTx(
        context,
        connection: conn,
        kind: sq.kind,
      )) {
        return;
      }
    }
    if (!mounted) return;
    final my = ws.lastSelectedMysqlObject;
    if (conn != null && conn.type == 'mysql' && my != null) {
      if (!await confirmOpenMysqlTableIfSqlTx(
        context,
        connection: conn,
        database: my.database,
        kind: my.kind,
      )) {
        return;
      }
    }
    if (!mounted) return;
    widget.workspace.value = widget.workspace.value.restoreLastSelectedObject();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _widthSpring.cubicDuration =
        context.motionDuration(QueryaMotion.sidebarCubic);
    _widthSpring.cubicCurve = context.motionCurve(QueryaMotion.enter);
    _widthSpring.useSprings = QueryaSpring.springsEnabled(context);
  }

  Future<void> _restoreState() async {
    final width = await AppSettings.instance.getConnectionsPanelWidth();
    final visible = await AppSettings.instance.getSidebarVisible();
    if (!mounted) return;
    final clamped = _clampLeftWidth(width, _lastMaxWidth);
    _lastExpandedWidth = clamped;
    _sidebarVisible = visible;
    widget.onSidebarVisibilityChanged?.call(visible);
    final targetW = visible ? clamped : 0.0;
    _widthSpring.jumpTo(targetW);
  }

  void toggleSidebar({bool? visible}) {
    final target = visible ?? !_sidebarVisible;
    _sidebarVisible = target;
    widget.onSidebarVisibilityChanged?.call(target);
    _widthSpring.useSprings = QueryaSpring.springsEnabled(context);
    final targetWidth = target ? _lastExpandedWidth : 0.0;
    _widthSpring.animateTo(targetWidth);
    unawaited(AppSettings.instance.setSidebarVisible(target));
  }

  void _onWidthSpringChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _schedulePersistAfterSettle() {
    _widthPersist.markDirty();
    final pending = _persistWhenSettled;
    if (pending != null) {
      _widthSpring.removeListener(pending);
    }
    void listener() {
      if (_widthSpring.isAnimating) return;
      _widthSpring.removeListener(listener);
      _persistWhenSettled = null;
      if (_sidebarVisible) {
        unawaited(_widthPersist.persist(_lastExpandedWidth));
      }
    }

    _persistWhenSettled = listener;
    if (_widthSpring.isAnimating) {
      _widthSpring.addListener(listener);
    } else {
      listener();
    }
  }

  @override
  void dispose() {
    final pending = _persistWhenSettled;
    if (pending != null) {
      _widthSpring.removeListener(pending);
      _persistWhenSettled = null;
    }
    if (_sidebarVisible) {
      _widthPersist.disposeFlush(_lastExpandedWidth);
    }
    _widthSpring.removeListener(_onWidthSpringChanged);
    _widthSpring.dispose();
    super.dispose();
  }

  double _clampLeftWidth(double raw, double maxWidth) {
    final maxLeft = maxWidth - _resizeHandleWidth - _minWorkspaceWidth;
    if (maxLeft <= 0) return 0;
    if (maxLeft < _minLeftWidth) return raw.clamp(0, maxLeft);
    return raw.clamp(_minLeftWidth, math.min(_maxLeftWidth, maxLeft));
  }

  @override
  material.Widget build(material.BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _lastMaxWidth = constraints.maxWidth;
        final currentW = _widthSpring.value.clamp(0.0, constraints.maxWidth);
        final progress = _lastExpandedWidth > 0
            ? (currentW / _lastExpandedWidth).clamp(0.0, 1.0)
            : 0.0;
        final currentHandleW =
            (progress * _resizeHandleWidth).clamp(0.0, _resizeHandleWidth);
        final handleOpacity = (progress * 5.0).clamp(0.0, 1.0);
        final contentOpacity = (progress * 2.2).clamp(0.0, 1.0);
        final parallaxOffset = (progress - 1.0) * 36.0;
        final isCollapsed =
            currentW <= _collapseThreshold || contentOpacity <= 0.0;

        final slot = material.RepaintBoundary(
          child: ConnectionsPanelSlot(
            connectionsPanelKey: widget.connectionsPanelKey,
            workspace: widget.workspace,
            onConnectionSelected: widget.onConnectionSelected,
            onRedisDatabaseSelected:
                widget.onRedisDatabaseSelected,
            onMongoDBDatabaseSelected:
                widget.onMongoDBDatabaseSelected,
            onMongoCollectionSelected:
                widget.onMongoCollectionSelected,
            onPostgresObjectSelected:
                widget.onPostgresObjectSelected,
            onPostgresOpenSqlWorkspace:
                widget.onPostgresOpenSqlWorkspace,
            onMysqlObjectSelected: widget.onMysqlObjectSelected,
            onMysqlOpenSqlWorkspace:
                widget.onMysqlOpenSqlWorkspace,
            onSqliteObjectSelected:
                widget.onSqliteObjectSelected,
            onSqliteOpenSqlWorkspace:
                widget.onSqliteOpenSqlWorkspace,
            onExtensionObjectSelected:
                widget.onExtensionObjectSelected,
          ),
        );

        final material.Widget slotContent;
        if (isCollapsed) {
          slotContent = Offstage(
            offstage: true,
            child: TickerMode(
              enabled: false,
              child: slot,
            ),
          );
        } else if (contentOpacity < 1.0) {
          slotContent = Opacity(
            opacity: contentOpacity,
            child: slot,
          );
        } else {
          slotContent = slot;
        }

        final material.Widget positionedSlot =
            (isCollapsed || parallaxOffset.abs() <= 0.001)
                ? slotContent
                : Transform.translate(
                    offset: Offset(parallaxOffset, 0),
                    child: slotContent,
                  );

        final handleWidget = IgnorePointer(
          ignoring: currentW <= 20.0 || !_sidebarVisible,
          child: QueryaSplitHandle(
            key: const Key('main_content_resize_handle'),
            axis: Axis.horizontal,
            semanticsLabel:
                'Resize connections and workspace panes',
            onDragDelta: (dx) {
              final ml = constraints.maxWidth -
                  _resizeHandleWidth -
                  _minWorkspaceWidth;
              if (ml <= 0) return;
              final nextW = _clampLeftWidth(
                _widthSpring.value + dx,
                constraints.maxWidth,
              );
              _lastExpandedWidth = nextW;
              _widthSpring.jumpTo(nextW);
            },
            onDiscreteResize: () => _widthPersist
                .onDiscreteResize(() => _lastExpandedWidth),
            onDragEnd: (details) {
              _widthPersist.cancelDiscreteTimer();
              final velocity = details.primaryVelocity ??
                  details.velocity.pixelsPerSecond.dx;
              final useSprings =
                  QueryaSpring.springsEnabled(context);
              _widthSpring.useSprings = useSprings;
              if (_widthSpring.value < 100 && velocity < -50) {
                _sidebarVisible = false;
                widget.onSidebarVisibilityChanged?.call(false);
                _widthSpring.animateTo(0.0, velocity: velocity);
                unawaited(
                    AppSettings.instance.setSidebarVisible(false));
              } else {
                _sidebarVisible = true;
                widget.onSidebarVisibilityChanged?.call(true);
                _lastExpandedWidth = _clampLeftWidth(
                  _widthSpring.value,
                  constraints.maxWidth,
                );
                _widthSpring.animateTo(
                  _lastExpandedWidth,
                  velocity: velocity,
                );
                unawaited(
                    AppSettings.instance.setSidebarVisible(true));
                _schedulePersistAfterSettle();
              }
            },
          ),
        );

        final material.Widget handleContent;
        if (handleOpacity >= 1.0) {
          handleContent = handleWidget;
        } else if (handleOpacity <= 0.0) {
          handleContent = const material.SizedBox.shrink();
        } else {
          handleContent = Opacity(
            opacity: handleOpacity,
            child: handleWidget,
          );
        }

        final isAnimating = _widthSpring.isAnimating;
        final remainingWidth =
            math.max(0.0, constraints.maxWidth - currentW - currentHandleW);
        // While the sidebar slides, the workspace is laid out once at the width
        // it ends with and pinned to the right edge: it stands still and the
        // sidebar covers or uncovers its left side. Laid out at the full window
        // width and pinned left, its right side ran past the window and it
        // snapped to the narrower width when the sidebar finished opening.
        final settledWidth = _sidebarVisible
            ? math.max(
                0.0,
                constraints.maxWidth -
                    _clampLeftWidth(_lastExpandedWidth, constraints.maxWidth) -
                    _resizeHandleWidth,
              )
            : constraints.maxWidth;
        final workspaceLaidOutWidth =
            isAnimating ? settledWidth : remainingWidth;

        return Row(
          children: [
            ClipRect(
              child: SizedBox(
                width: currentW,
                child: OverflowBox(
                  minWidth: _lastExpandedWidth,
                  maxWidth: _lastExpandedWidth,
                  alignment: Alignment.topLeft,
                  child: positionedSlot,
                ),
              ),
            ),
            if (!isCollapsed)
              SizedBox(
                width: currentHandleW,
                child: ClipRect(
                  child: OverflowBox(
                    minWidth: _resizeHandleWidth,
                    maxWidth: _resizeHandleWidth,
                    alignment: Alignment.center,
                    child: handleContent,
                  ),
                ),
              ),
            Expanded(
              key: const ValueKey('main_content_workspace_expanded'),
              child: ClipRect(
                child: OverflowBox(
                  alignment:
                      isAnimating ? Alignment.topRight : Alignment.topLeft,
                  minWidth: workspaceLaidOutWidth,
                  maxWidth: workspaceLaidOutWidth,
                  child: material.RepaintBoundary(
                    child: ValueListenableBuilder<MainScreenWorkspaceState>(
                      valueListenable: widget.workspace,
                      builder: (context, ws, _) {
                        return WorkspacePanel(
                          activeConnection: ws.activeConnection,
                          selectedRedisDb: ws.activeRedisDb,
                          selectedMongoDb: ws.activeMongoDB,
                          selectedPostgresObject: ws.selectedPostgresObject,
                          postgresSqlTabRequestToken:
                              ws.postgresSqlTabRequestToken,
                          postgresSqlEditorContext:
                              ws.postgresSqlEditorContext,
                          postgresSqlEditorContextToken:
                              ws.postgresSqlEditorContextToken,
                          selectedMysqlObject: ws.selectedMysqlObject,
                          mysqlSqlTabRequestToken: ws.mysqlSqlTabRequestToken,
                          selectedSqliteObject: ws.selectedSqliteObject,
                          sqliteSqlTabRequestToken: ws.sqliteSqlTabRequestToken,
                          selectedExtensionObject: ws.selectedExtensionObject,
                          lastSelectedPostgresObject:
                              ws.lastSelectedPostgresObject,
                          lastSelectedMysqlObject: ws.lastSelectedMysqlObject,
                          lastSelectedSqliteObject: ws.lastSelectedSqliteObject,
                          lastSelectedExtensionObject:
                              ws.lastSelectedExtensionObject,
                          lastSelectedMongoDb: ws.lastSelectedMongoDb,
                          lastSelectedMongoCollection:
                              ws.lastSelectedMongoCollection,
                          lastSelectedRedisDb: ws.lastSelectedRedisDb,
                          selectedRedisKey: ws.selectedRedisKey,
                          lastSelectedRedisKey: ws.lastSelectedRedisKey,
                          onNavigateHome: () {
                            widget.workspace.value =
                                widget.workspace.value.unselectActiveObject();
                          },
                          onRestoreLastSelectedObject: () {
                            unawaited(_restoreLastSelectedObject());
                          },
                          isReadOnly: ws.isReadOnly,
                          onRequestNewConnection: widget.onRequestNewConnection,
                          onRequestNewConnectionFromUrl:
                              widget.onRequestNewConnectionFromUrl,
                          onRequestOpenSqlite: widget.onRequestOpenSqlite,
                          onRequestLaunchDemo: widget.onRequestLaunchDemo,
                          onRequestOpenTour: widget.onRequestOpenTour,
                          onOpenConnection: widget.onOpenConnection,
                          initialMongoCollection: widget.initialMongoCollection,
                          selectedMongoCollection: ws.selectedMongoCollection,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Rebuilds [ConnectionsPanel] only when the selected connection id changes.
class ConnectionsPanelSlot extends StatefulWidget {
  const ConnectionsPanelSlot({
    super.key,
    required this.connectionsPanelKey,
    required this.workspace,
    required this.onConnectionSelected,
    required this.onPostgresObjectSelected,
    required this.onMysqlObjectSelected,
    required this.onSqliteObjectSelected,
    required this.onRedisDatabaseSelected,
    required this.onMongoDBDatabaseSelected,
    required this.onMongoCollectionSelected,
    required this.onPostgresOpenSqlWorkspace,
    required this.onMysqlOpenSqlWorkspace,
    required this.onSqliteOpenSqlWorkspace,
    required this.onExtensionObjectSelected,
  });

  final GlobalKey<ConnectionsPanelState> connectionsPanelKey;
  final ValueNotifier<MainScreenWorkspaceState> workspace;
  final void Function(ConnectionRow) onConnectionSelected;
  final void Function(
    ConnectionRow,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  ) onPostgresObjectSelected;
  final void Function(
    ConnectionRow,
    String database,
    String name,
    MysqlObjectKind kind,
  ) onMysqlObjectSelected;
  final void Function(
    ConnectionRow,
    String name,
    SqliteObjectKind kind,
  ) onSqliteObjectSelected;
  final void Function(ConnectionRow, int) onRedisDatabaseSelected;
  final void Function(ConnectionRow, String) onMongoDBDatabaseSelected;
  final void Function(ConnectionRow, String, String) onMongoCollectionSelected;
  final OnPostgresOpenSqlWorkspace onPostgresOpenSqlWorkspace;
  final void Function(ConnectionRow) onMysqlOpenSqlWorkspace;
  final void Function(ConnectionRow) onSqliteOpenSqlWorkspace;
  final void Function(
    ConnectionRow,
    String database,
    String name,
  ) onExtensionObjectSelected;

  @override
  State<ConnectionsPanelSlot> createState() => ConnectionsPanelSlotState();
}

class ConnectionsPanelSlotState extends State<ConnectionsPanelSlot> {
  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_onWorkspaceChanged);
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_onWorkspaceChanged);
    super.dispose();
  }

  void _onWorkspaceChanged() {
    setState(() {});
  }

  @override
  material.Widget build(material.BuildContext context) {
    final ws = widget.workspace.value;
    return ConnectionsPanel(
      key: widget.connectionsPanelKey,
      selectedConnectionId: ws.activeConnection?.id,
      selectedPostgresObject: ws.selectedPostgresObject,
      selectedMysqlObject: ws.selectedMysqlObject,
      selectedSqliteObject: ws.selectedSqliteObject,
      selectedExtensionObject: ws.selectedExtensionObject,
      selectedRedisDb: ws.activeRedisDb,
      selectedMongoDb: ws.activeMongoDB,
      selectedMongoCollection: ws.selectedMongoCollection,
      onConnectionSelected: widget.onConnectionSelected,
      onRedisDatabaseSelected: widget.onRedisDatabaseSelected,
      onMongoDBDatabaseSelected: widget.onMongoDBDatabaseSelected,
      onMongoCollectionSelected: widget.onMongoCollectionSelected,
      onPostgresObjectSelected: widget.onPostgresObjectSelected,
      onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
      onMysqlObjectSelected: widget.onMysqlObjectSelected,
      onMysqlOpenSqlWorkspace: widget.onMysqlOpenSqlWorkspace,
      onSqliteObjectSelected: widget.onSqliteObjectSelected,
      onSqliteOpenSqlWorkspace: widget.onSqliteOpenSqlWorkspace,
      onExtensionObjectSelected: widget.onExtensionObjectSelected,
      onConnectionRemoved: (id) {
        // The open workspace belonged to the removed connection: go home.
        if (widget.workspace.value.activeConnection?.id != id) return;
        widget.workspace.value = MainScreenWorkspaceState.empty;
        QueryaShellStatus.instance.clear();
      },
    );
  }
}
