import 'dart:async';
import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/actions/querya_command_host.dart';
import 'package:querya_desktop/core/actions/querya_schema_object.dart';
import 'package:querya_desktop/core/actions/querya_schema_object_loader.dart';
import 'package:querya_desktop/features/command_palette/command_palette_dialog.dart';
import 'package:querya_desktop/features/command_palette/quick_switcher_dialog.dart';
import 'package:querya_desktop/core/actions/sql_editor_actions.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/actions/sql_editor_global_actions.dart';
import 'package:querya_desktop/core/demo/demo_playground_service.dart';
import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/platform/file_launch_service.dart';
import 'package:querya_desktop/core/security/safe_mode.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/extensions/sandbox/unsandboxed_launch_consent_gate.dart';
import 'package:querya_desktop/features/extensions/presentation/widgets/unsandboxed_driver_consent_dialog.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:querya_desktop/features/connections/new_connection_url_dialog.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:querya_desktop/features/connections/sqlite_connection_form.dart';
import 'package:querya_desktop/core/ui/querya_shell_status.dart';
import 'package:querya_desktop/core/unsaved_work_guard.dart';
import 'package:querya_desktop/features/main_screen/querya_status_bar.dart';
import 'package:querya_desktop/features/main_screen/safe_mode_unlock_dialog.dart';
import 'package:querya_desktop/features/main_screen/querya_window_title_bar.dart';
import 'package:querya_desktop/features/macos/querya_platform_menu_bar.dart';
import 'package:querya_desktop/features/mysql/mysql_object_kind.dart';
import 'package:querya_desktop/features/mysql/mysql_sql_tx_guard.dart';
import 'package:querya_desktop/features/onboarding/welcome_tour_dialog.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgres_sql_tx_guard.dart';
import 'package:querya_desktop/features/sqlite/sqlite_sql_tx_guard.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'main_screen_workspace_state.dart';
import 'main_content_split.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final GlobalKey<ConnectionsPanelState> _connectionsPanelKey =
      GlobalKey<ConnectionsPanelState>();
  final GlobalKey<MainContentSplitState> _splitKey =
      GlobalKey<MainContentSplitState>();

  final ValueNotifier<MainScreenWorkspaceState> _workspace =
      ValueNotifier(MainScreenWorkspaceState.empty);
  final ValueNotifier<bool> _isSidebarVisible = ValueNotifier(true);
  bool _openingConnectionDialog = false;
  String? _pendingMongoCollection;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    UnsandboxedLaunchConsentGate.instance.handler = (details) {
      if (!mounted) return Future.value(false);
      return showUnsandboxedDriverConsentDialog(context, details);
    };

    // Files Finder opens while the window is up (#1589).
    FileLaunchService.instance.pendingRevision.addListener(_onFilesQueued);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final completed = await AppSettings.instance.getHasCompletedWelcomeTour();
      if (!completed && mounted) {
        final connections = await LocalDb.instance.getConnections();
        if (connections.isEmpty &&
            mounted &&
            !FileLaunchService.instance.hasPendingTargets) {
          _onOpenWelcomeTour();
        }
      }
      if (mounted) {
        await _handlePendingFileLaunch();
      }
    });
  }

  void _onFilesQueued() {
    if (mounted) unawaited(_handlePendingFileLaunch());
  }

  @override
  void dispose() {
    FileLaunchService.instance.pendingRevision.removeListener(_onFilesQueued);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    UnsandboxedLaunchConsentGate.instance.handler = null;
    _safeModeRelockTimer?.cancel();
    _workspace.dispose();
    _isSidebarVisible.dispose();
    super.dispose();
  }

  Timer? _safeModeRelockTimer;

  /// Toggles the read-only lock. Turning it off for a Production connection
  /// (Safe Mode) needs a typed confirmation and re-locks after
  /// [kSafeModeUnlockDuration].
  Future<void> _toggleReadOnly() async {
    final ws = _workspace.value;
    final connection = ws.activeConnection;
    if (connection == null) return;

    if (ws.isReadOnly &&
        safeModeRequiresConfirmation(connection.environment)) {
      final confirmed = await showSafeModeUnlockDialog(
        context: context,
        connectionName: connection.name,
      );
      if (!confirmed || !mounted) return;
      final current = _workspace.value;
      if (current.activeConnection?.id != connection.id || !current.isReadOnly) {
        return;
      }
      _workspace.value = current.toggleReadOnly();
      _safeModeRelockTimer?.cancel();
      _safeModeRelockTimer = Timer(kSafeModeUnlockDuration, () {
        if (!mounted) return;
        final latest = _workspace.value;
        if (latest.activeConnection?.id == connection.id &&
            !latest.isReadOnly) {
          _workspace.value = latest.toggleReadOnly();
          showAppToast(
            context: context,
            message: '${connection.name} is read-only again',
          );
        }
      });
      return;
    }

    _safeModeRelockTimer?.cancel();
    _workspace.value = ws.toggleReadOnly();
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final isMac = Platform.isMacOS;
    final isCmdOrCtrl = isMac
        ? (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)
        : HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    final physical = event.physicalKey;
    final logical = event.logicalKey;

    // 1. Execute SQL, as in the editor: Ctrl/Cmd+Enter and Ctrl/Cmd+R run the
    // selection or the statement at the cursor; F5 and Ctrl/Cmd+Shift+Enter
    // run the whole script.
    final isEnter = physical == PhysicalKeyboardKey.enter ||
        physical == PhysicalKeyboardKey.numpadEnter ||
        logical == LogicalKeyboardKey.enter ||
        logical == LogicalKeyboardKey.numpadEnter;
    final isF5 = physical == PhysicalKeyboardKey.f5 ||
        logical == LogicalKeyboardKey.f5;
    final isKeyR = physical == PhysicalKeyboardKey.keyR ||
        logical == LogicalKeyboardKey.keyR ||
        logical == const LogicalKeyboardKey(0x0000043a); // Russian 'к'

    final runScript = isF5 || (isCmdOrCtrl && isShift && !isAlt && isEnter);
    final runStatement = isCmdOrCtrl &&
        !isShift &&
        !isAlt &&
        (isEnter || isKeyR);
    if ((runScript || runStatement) &&
        SqlEditorCommandBridge.instance.canExecute) {
      if (runScript) {
        SqlEditorCommandBridge.instance.invokeExecute();
      } else {
        SqlEditorCommandBridge.instance.invokeExecuteStatement();
      }
      return true;
    }

    // Preferences: Ctrl+, / Cmd+, (Physical comma, Logical comma, Russian 'б')
    final isComma = physical == PhysicalKeyboardKey.comma ||
        logical == LogicalKeyboardKey.comma ||
        logical == const LogicalKeyboardKey(0x00000431); // Russian 'б'
    if (isCmdOrCtrl && !isShift && !isAlt && isComma) {
      showPreferencesDialog(context);
      return true;
    }

    // 2. Toggle Left Sidebar: Ctrl+B / Cmd+B (Physical B, Logical B, Russian 'и')
    final isKeyB = physical == PhysicalKeyboardKey.keyB ||
        logical == LogicalKeyboardKey.keyB ||
        logical == const LogicalKeyboardKey(0x00000438); // Russian 'и'
    if (isCmdOrCtrl && !isShift && !isAlt && isKeyB) {
      _splitKey.currentState?.toggleSidebar();
      return true;
    }

    // Command Palette: Ctrl+P / Cmd+P (Physical P, Logical P, Russian 'з')
    final isKeyP = physical == PhysicalKeyboardKey.keyP ||
        logical == LogicalKeyboardKey.keyP ||
        logical == const LogicalKeyboardKey(0x00000437) || // з
        logical == const LogicalKeyboardKey(0x00000417); // З
    if (isCmdOrCtrl && !isShift && !isAlt && isKeyP) {
      final ctx = FocusManager.instance.primaryFocus?.context ?? context;
      unawaited(showCommandPalette(ctx));
      return true;
    }

    // Quick Switcher: Ctrl+K / Cmd+K (Physical K, Logical K, Russian 'л')
    final isKeyK = physical == PhysicalKeyboardKey.keyK ||
        logical == LogicalKeyboardKey.keyK ||
        logical == const LogicalKeyboardKey(0x0000043b) || // л
        logical == const LogicalKeyboardKey(0x0000041b); // Л
    if (isCmdOrCtrl && !isShift && !isAlt && isKeyK) {
      _openQuickSwitcher();
      return true;
    }

    // 3. New Connection / New Query Tab: (Physical N, Logical N, Russian 'т')
    final isKeyN = physical == PhysicalKeyboardKey.keyN ||
        logical == LogicalKeyboardKey.keyN ||
        logical == const LogicalKeyboardKey(0x00000442); // Russian 'т'
    if (isCmdOrCtrl && !isAlt && isKeyN) {
      if (isShift) {
        // Ctrl+Shift+N: New Query
        final ctx = FocusManager.instance.primaryFocus?.context ?? context;
        Actions.maybeInvoke(ctx, const NewSqlIntent());
      } else {
        // Ctrl+N: New Database Connection
        unawaited(_onNewDatabaseConnectionFromMenu());
      }
      return true;
    }

    // New Query Tab: Ctrl+T / Cmd+T (Physical T, Logical T, Russian 'е')
    final isKeyT = physical == PhysicalKeyboardKey.keyT ||
        logical == LogicalKeyboardKey.keyT ||
        logical == const LogicalKeyboardKey(0x00000435); // Russian 'е'
    if (isCmdOrCtrl && !isShift && !isAlt && isKeyT) {
      final ctx = FocusManager.instance.primaryFocus?.context ?? context;
      final handled = Actions.maybeInvoke(ctx, const NewSqlIntent());
      if (handled == null) {
        SqlEditorCommandBridge.instance.invokeNew();
      }
      return true;
    }

    // Close Query Tab: Ctrl+W / Cmd+W (Physical W, Logical W, Russian 'ц')
    final isKeyW = physical == PhysicalKeyboardKey.keyW ||
        logical == LogicalKeyboardKey.keyW ||
        logical == const LogicalKeyboardKey(0x00000446); // Russian 'ц'
    if (isCmdOrCtrl && !isShift && !isAlt && isKeyW) {
      final ctx = FocusManager.instance.primaryFocus?.context ?? context;
      final handled = Actions.maybeInvoke(ctx, const CloseSqlTabIntent());
      if (handled == null) {
        SqlEditorCommandBridge.instance.invokeCloseTab();
      }
      return true;
    }

    // Next / Prev Tab: Ctrl+Tab / Ctrl+Shift+Tab
    final isTab = physical == PhysicalKeyboardKey.tab ||
        logical == LogicalKeyboardKey.tab;
    if (isCmdOrCtrl && !isAlt && isTab) {
      final ctx = FocusManager.instance.primaryFocus?.context ?? context;
      if (isShift) {
        final handled = Actions.maybeInvoke(ctx, const PrevSqlTabIntent());
        if (handled == null) {
          SqlEditorCommandBridge.instance.invokePrevTab();
        }
      } else {
        final handled = Actions.maybeInvoke(ctx, const NextSqlTabIntent());
        if (handled == null) {
          SqlEditorCommandBridge.instance.invokeNextTab();
        }
      }
      return true;
    }

    // 4. Open SQL: Ctrl+O / Cmd+O (Physical O, Logical O, Russian 'щ')
    final isKeyO = physical == PhysicalKeyboardKey.keyO ||
        logical == LogicalKeyboardKey.keyO ||
        logical == const LogicalKeyboardKey(0x00000449); // Russian 'щ'
    if (isCmdOrCtrl && !isShift && !isAlt && isKeyO) {
      final ctx = FocusManager.instance.primaryFocus?.context ?? context;
      Actions.maybeInvoke(ctx, const OpenSqlIntent());
      return true;
    }

    // 5. Save SQL: Ctrl+S / Cmd+S (Physical S, Logical S, Russian 'ы')
    final isKeyS = physical == PhysicalKeyboardKey.keyS ||
        logical == LogicalKeyboardKey.keyS ||
        logical == const LogicalKeyboardKey(0x0000044b); // Russian 'ы'
    if (isCmdOrCtrl && !isShift && !isAlt && isKeyS) {
      final ctx = FocusManager.instance.primaryFocus?.context ?? context;
      Actions.maybeInvoke(ctx, const SaveSqlIntent());
      return true;
    }

    // 6. Tutorial & Welcome: F1 or Ctrl+Shift+H / Cmd+Shift+H (Physical H, Logical H, Russian 'р')
    final isF1 = physical == PhysicalKeyboardKey.f1 ||
        logical == LogicalKeyboardKey.f1;
    final isKeyH = physical == PhysicalKeyboardKey.keyH ||
        logical == LogicalKeyboardKey.keyH ||
        logical == const LogicalKeyboardKey(0x00000440); // Russian 'р'
    if (isF1 || (isCmdOrCtrl && isShift && isKeyH)) {
      _onOpenWelcomeTour();
      return true;
    }

    // 7. Home / Start Screen: Ctrl+Shift+0 / Cmd+Shift+0
    final isDigit0 = physical == PhysicalKeyboardKey.digit0 ||
        physical == PhysicalKeyboardKey.numpad0 ||
        logical == LogicalKeyboardKey.digit0 ||
        logical == LogicalKeyboardKey.numpad0;
    if (isCmdOrCtrl && isShift && isDigit0) {
      _onGoHome();
      return true;
    }

    return false;
  }

  Future<bool> _allowUnsavedNavigation() {
    return confirmDiscardUnsavedWorkIfNeeded(context);
  }

  void _onConnectionSelected(ConnectionRow connection) {
    unawaited(_selectConnection(connection));
  }

  Future<void> _selectConnection(ConnectionRow connection) async {
    if (!await _allowUnsavedNavigation()) return;
    if (!mounted) return;
    final prevId = _workspace.value.activeConnection?.id;
    _workspace.value = _workspace.value.selectConnection(connection);
    if (prevId != connection.id) {
      QueryaShellStatus.instance.clear();
      _pendingMongoCollection = null;
    }
    final id = connection.id;
    if (id != null) {
      unawaited(AppSettings.instance.recordRecentConnection(id));
    }
  }

  void _onPostgresObjectSelected(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  ) {
    unawaited(_selectPostgresObject(
      connection,
      database,
      schema,
      name,
      kind,
    ));
  }

  Future<void> _selectPostgresObject(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  ) async {
    final ws = _workspace.value;
    final cur = ws.selectedPostgresObject;
    final same = ws.activeConnection?.id == connection.id &&
        cur != null &&
        cur.database == database &&
        cur.schema == schema &&
        cur.name == name &&
        cur.kind == kind;
    if (same) return;
    if (!await _allowUnsavedNavigation()) return;
    if (!mounted) return;
    if (!await confirmOpenPostgresTableIfSqlTx(
      context,
      connection: connection,
      database: database,
      kind: kind,
    )) {
      return;
    }
    if (!mounted) return;
    _workspace.value = _workspace.value.selectPostgresObject(
      connection,
      database,
      schema,
      name,
      kind,
    );
  }

  void _onMysqlObjectSelected(
    ConnectionRow connection,
    String database,
    String name,
    MysqlObjectKind kind,
  ) {
    unawaited(_selectMysqlObject(connection, database, name, kind));
  }

  Future<void> _selectMysqlObject(
    ConnectionRow connection,
    String database,
    String name,
    MysqlObjectKind kind,
  ) async {
    final ws = _workspace.value;
    final cur = ws.selectedMysqlObject;
    final same = ws.activeConnection?.id == connection.id &&
        cur != null &&
        cur.database == database &&
        cur.name == name &&
        cur.kind == kind;
    if (same) return;
    if (!await _allowUnsavedNavigation()) return;
    if (!mounted) return;
    if (!await confirmOpenMysqlTableIfSqlTx(
      context,
      connection: connection,
      database: database,
      kind: kind,
    )) {
      return;
    }
    if (!mounted) return;
    _workspace.value = _workspace.value.selectMysqlObject(
      connection,
      database,
      name,
      kind,
    );
  }

  void _onRedisDatabaseSelected(ConnectionRow connection, int database) {
    unawaited(_selectRedisDatabase(connection, database));
  }

  Future<void> _selectRedisDatabase(
    ConnectionRow connection,
    int database,
  ) async {
    final ws = _workspace.value;
    if (ws.activeConnection?.id == connection.id &&
        ws.activeRedisDb == database) {
      return;
    }
    if (!await _allowUnsavedNavigation()) return;
    if (!mounted) return;
    _workspace.value = _workspace.value.selectRedisDb(connection, database);
  }

  void _onMongoDBDatabaseSelected(ConnectionRow connection, String database) {
    unawaited(_selectMongoDatabase(connection, database));
  }

  Future<void> _selectMongoDatabase(
    ConnectionRow connection,
    String database,
  ) async {
    final ws = _workspace.value;
    if (ws.activeConnection?.id == connection.id &&
        ws.activeMongoDB == database &&
        ws.selectedMongoCollection == null) {
      return;
    }
    if (!await _allowUnsavedNavigation()) return;
    if (!mounted) return;
    setState(() => _pendingMongoCollection = null);
    _workspace.value = _workspace.value.selectMongoDb(connection, database);
  }

  void _onMongoCollectionSelected(
    ConnectionRow connection,
    String database,
    String collection,
  ) {
    unawaited(_selectMongoCollection(connection, database, collection));
  }

  Future<void> _selectMongoCollection(
    ConnectionRow connection,
    String database,
    String collection,
  ) async {
    final ws = _workspace.value;
    if (ws.activeConnection?.id == connection.id &&
        ws.activeMongoDB == database &&
        ws.selectedMongoCollection == collection) {
      return;
    }
    if (!await _allowUnsavedNavigation()) return;
    if (!mounted) return;
    setState(() => _pendingMongoCollection = collection);
    _workspace.value =
        _workspace.value.selectMongoCollection(connection, database, collection);
  }

  void _onPostgresOpenSqlWorkspace(
    ConnectionRow connection, {
    String? database,
    String? schema,
    String? name,
    PostgresObjectKind? kind,
  }) {
    unawaited(_openPostgresSqlWorkspace(
      connection,
      database: database,
      schema: schema,
      name: name,
      kind: kind,
    ));
  }

  Future<void> _openPostgresSqlWorkspace(
    ConnectionRow connection, {
    String? database,
    String? schema,
    String? name,
    PostgresObjectKind? kind,
  }) async {
    if (!await _allowUnsavedNavigation()) return;
    if (!mounted) return;
    _workspace.value = _workspace.value.openPostgresSqlWorkspace(
      connection,
      seedDatabase: database,
      seedSchema: schema,
      seedName: name,
      seedKind: kind,
    );
  }

  void _onMysqlOpenSqlWorkspace(ConnectionRow connection) {
    unawaited(_openMysqlSqlWorkspace(connection));
  }

  Future<void> _openMysqlSqlWorkspace(ConnectionRow connection) async {
    if (!await _allowUnsavedNavigation()) return;
    if (!mounted) return;
    _workspace.value = _workspace.value.openMysqlSqlWorkspace(connection);
  }

  void _onSqliteObjectSelected(
    ConnectionRow connection,
    String name,
    SqliteObjectKind kind,
  ) {
    unawaited(_selectSqliteObject(connection, name, kind));
  }

  Future<void> _selectSqliteObject(
    ConnectionRow connection,
    String name,
    SqliteObjectKind kind,
  ) async {
    final ws = _workspace.value;
    final cur = ws.selectedSqliteObject;
    final same = ws.activeConnection?.id == connection.id &&
        cur != null &&
        cur.name == name &&
        cur.kind == kind;
    if (same) return;
    if (!await _allowUnsavedNavigation()) return;
    if (!mounted) return;
    if (!await confirmOpenSqliteTableIfSqlTx(
      context,
      connection: connection,
      kind: kind,
    )) {
      return;
    }
    if (!mounted) return;
    _workspace.value = _workspace.value.selectSqliteObject(
      connection,
      name,
      kind,
    );
  }

  void _onSqliteOpenSqlWorkspace(ConnectionRow connection) {
    unawaited(_openSqliteSqlWorkspace(connection));
  }

  Future<void> _openSqliteSqlWorkspace(ConnectionRow connection) async {
    if (!await _allowUnsavedNavigation()) return;
    if (!mounted) return;
    _workspace.value = _workspace.value.openSqliteSqlWorkspace(connection);
  }

  void _onExtensionObjectSelected(
    ConnectionRow connection,
    String database,
    String name,
  ) {
    unawaited(_selectExtensionObject(connection, database, name));
  }

  Future<void> _selectExtensionObject(
    ConnectionRow connection,
    String database,
    String name,
  ) async {
    final ws = _workspace.value;
    final cur = ws.selectedExtensionObject;
    final same = ws.activeConnection?.id == connection.id &&
        cur != null &&
        cur.database == database &&
        cur.name == name;
    if (same) return;
    if (!await _allowUnsavedNavigation()) return;
    if (!mounted) return;
    _workspace.value = _workspace.value.selectExtensionObject(
      connection,
      database,
      name,
    );
  }

  void _openQuickSwitcher([String query = '']) {
    final ctx = FocusManager.instance.primaryFocus?.context ?? context;
    final ws = _workspace.value;
    final conn = ws.activeConnection;
    unawaited(showQuickSwitcher(
      ctx,
      initialQuery: query,
      load: () => QueryaSchemaObjectLoader.load(
        connection: conn,
        database: ws.selectedPostgresObject?.database ??
            ws.selectedMysqlObject?.database ??
            ws.selectedExtensionObject?.database ??
            conn?.databaseName,
        mongoDatabase: ws.activeMongoDB ?? conn?.databaseName,
      ),
    ));
  }

  void _onOpenSchemaObject(QueryaSchemaObject object) {
    final conn = _workspace.value.activeConnection;
    if (conn == null) return;
    final type = conn.type.toLowerCase();
    switch (object.kind) {
      case QueryaSchemaObjectKind.table:
      case QueryaSchemaObjectKind.view:
      case QueryaSchemaObjectKind.materializedView:
        if (type == 'postgres' || type == 'postgresql') {
          _onPostgresObjectSelected(
            conn,
            object.database ?? conn.databaseName ?? '',
            object.schema ?? 'public',
            object.name,
            switch (object.kind) {
              QueryaSchemaObjectKind.view => PostgresObjectKind.view,
              QueryaSchemaObjectKind.materializedView =>
                PostgresObjectKind.materializedView,
              _ => PostgresObjectKind.table,
            },
          );
          return;
        }
        if (type == 'mysql') {
          _onMysqlObjectSelected(
            conn,
            object.database ?? conn.databaseName ?? '',
            object.name,
            object.kind == QueryaSchemaObjectKind.view
                ? MysqlObjectKind.view
                : MysqlObjectKind.table,
          );
          return;
        }
        if (type == 'sqlite') {
          _onSqliteObjectSelected(
            conn,
            object.name,
            object.kind == QueryaSchemaObjectKind.view
                ? SqliteObjectKind.view
                : SqliteObjectKind.table,
          );
          return;
        }
        if (conn.isExtensionDriver) {
          _onExtensionObjectSelected(
            conn,
            object.database ?? conn.databaseName ?? '',
            object.name,
          );
        }
      case QueryaSchemaObjectKind.collection:
        _onMongoCollectionSelected(
          conn,
          object.database ?? conn.databaseName ?? '',
          object.name,
        );
    }
  }

  void _openSqlWorkspaceForConnection(ConnectionRow connection) {
    switch (connection.type) {
      case 'postgresql':
        _onPostgresOpenSqlWorkspace(connection);
      case 'mysql':
        _onMysqlOpenSqlWorkspace(connection);
      case 'sqlite':
        _onSqliteOpenSqlWorkspace(connection);
      default:
        if (ExtensionDriverCatalog.isExtensionDriverConnection(connection)) {
          unawaited(_selectConnection(connection));
        }
    }
  }

  Future<void> _openNewConnectionFromHero() async {
    final row = await promptCreateConnection(context);
    if (!mounted || row == null) return;
    await LocalDb.instance.addConnection(row);
    await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
  }

  Future<void> _onNewDatabaseConnectionFromMenu() async {
    if (_openingConnectionDialog) return;
    _openingConnectionDialog = true;
    try {
      // Menu overlay context is torn down before the connection form opens.
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      final row = await promptCreateConnection(context, folderId: null);
      if (!mounted || row == null) return;
      await LocalDb.instance.addConnection(row);
      await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
    } finally {
      _openingConnectionDialog = false;
    }
  }

  Future<void> _onNewDatabaseConnectionFromUrl() async {
    if (_openingConnectionDialog) return;
    _openingConnectionDialog = true;
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      final row = await showNewConnectionUrlDialog(context);
      if (!mounted || row == null) return;
      await LocalDb.instance.addConnection(row);
      await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
    } finally {
      _openingConnectionDialog = false;
    }
  }

  Future<void> _openSqliteFromHero() async {
    final row = await showSqliteConnectionForm(context);
    if (!mounted || row == null) return;
    await LocalDb.instance.addConnection(row);
    await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
  }

  void _onGoHome() {
    unawaited(_goHome());
  }

  Future<void> _goHome() async {
    if (!await _allowUnsavedNavigation()) return;
    if (!mounted) return;
    _workspace.value = MainScreenWorkspaceState.empty;
    QueryaShellStatus.instance.clear();
  }

  Future<void> _closeWorkspace() async {
    if (!await _allowUnsavedNavigation()) return;
    if (!mounted) return;
    _workspace.value = _workspace.value.unselectActiveObject();
  }

  bool _hasCloseableWorkspace(MainScreenWorkspaceState ws) {
    return ws.selectedPostgresObject != null ||
        ws.selectedMysqlObject != null ||
        ws.selectedSqliteObject != null ||
        ws.selectedExtensionObject != null ||
        ws.activeMongoDB != null ||
        ws.activeRedisDb != null;
  }

  void _onOpenWelcomeTour() {
    showWelcomeTourDialog(
      context,
      onLaunchDemo: _onLaunchDemoPlayground,
      onGoHome: _workspace.value.activeConnection != null ? _onGoHome : null,
    );
  }

  Future<void> _onLaunchDemoPlayground() async {
    try {
      final demoConn = await DemoPlaygroundService.getOrCreateDemoConnection();
      if (!mounted) return;
      await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
      _workspace.value = _workspace.value.selectConnection(demoConn);
      _onSqliteOpenSqlWorkspace(demoConn);
    } catch (_) {}
  }

  Future<void> _handlePendingFileLaunch() async {
    final targets = FileLaunchService.instance.consumePendingTargets();
    if (targets.isEmpty || !mounted) return;

    for (final target in targets) {
      if (!mounted) return;
      try {
        if (target.kind == FileLaunchKind.sqlite) {
          final conn = await FileLaunchService.instance
              .resolveOrRegisterSqliteConnection(target);
          if (!mounted) return;
          await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
          _workspace.value = _workspace.value.selectConnection(conn);
          _onSqliteOpenSqlWorkspace(conn);
        } else if (target.kind == FileLaunchKind.sql) {
          final sql = await FileLaunchService.instance.readSqlContent(target);
          if (!mounted) return;

          var conn = _workspace.value.activeConnection;
          if (conn == null) {
            final connections = await LocalDb.instance.getConnections();
            if (connections.isNotEmpty) {
              conn = connections.first;
            } else {
              final scratchRow = ConnectionRow(
                name: 'Local Scratch (${target.fileName})',
                type: 'sqlite',
                host: '',
                createdAt: DateTime.now().toUtc().toIso8601String(),
              );
              final id = await LocalDb.instance.addConnection(scratchRow);
              conn = scratchRow.copyWith(id: id);
              await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
            }
          }

          if (mounted) {
            _workspace.value = _workspace.value.selectConnection(conn);
            _openSqlWorkspaceForConnection(conn);
            SqlEditorCommandBridge.instance.openFileWithContent(
              sql: sql,
              filePath: target.path,
              title: target.fileName,
            );
          }
        }
      } catch (e) {
        if (!mounted) return;
        showAppToast(
          context: context,
          message: 'Failed to open file "${target.fileName}": $e',
          variant: AppToastVariant.error,
        );
      }
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    return ValueListenableBuilder<MainScreenWorkspaceState>(
      valueListenable: _workspace,
      builder: (context, workspace, _) {
        return QueryaCommandHost(
          onToggleSidebar: () => _splitKey.currentState?.toggleSidebar(),
          onNewConnection: () => unawaited(_onNewDatabaseConnectionFromMenu()),
          onReloadConnections: () => unawaited(
              _connectionsPanelKey.currentState?.reloadConnectionsFromDb() ??
                  Future<void>.value()),
          onShowQuickSwitcher: _openQuickSwitcher,
          onOpenSchemaObject: _onOpenSchemaObject,
          onGoHome:
              workspace.activeConnection != null ? _onGoHome : null,
          onCloseWorkspace: _hasCloseableWorkspace(workspace)
              ? () => unawaited(_closeWorkspace())
              : null,
          onConnect: workspace.activeConnection?.id != null
              ? () => _connectionsPanelKey.currentState
                  ?.connect(workspace.activeConnection!.id!)
              : null,
          onDisconnect: workspace.activeConnection != null
              ? () => unawaited(
                    _connectionsPanelKey.currentState
                            ?.disconnect(workspace.activeConnection!) ??
                        Future<void>.value(),
                  )
              : null,
          onReconnect: workspace.activeConnection != null
              ? () => unawaited(
                    _connectionsPanelKey.currentState
                            ?.reconnect(workspace.activeConnection!) ??
                        Future<void>.value(),
                  )
              : null,
          onToggleReadOnly: workspace.activeConnection != null
              ? () => unawaited(_toggleReadOnly())
              : null,
          onOpenWelcomeTour: _onOpenWelcomeTour,
          selectedConnectionId: workspace.activeConnection?.id,
          child: FocusScope(
          autofocus: true,
          child: material.CallbackShortcuts(
            bindings: {
              // New Database Connection: Ctrl+N / Cmd+N
              const material.SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ): () => unawaited(_onNewDatabaseConnectionFromMenu()),
              const material.SingleActivator(
                LogicalKeyboardKey.keyN,
                control: true,
              ): () => unawaited(_onNewDatabaseConnectionFromMenu()),

              // New Query Tab: Ctrl+Shift+N / Cmd+Shift+N
              const material.SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
                shift: true,
              ): () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const NewSqlIntent());
              },
              const material.SingleActivator(
                LogicalKeyboardKey.keyN,
                control: true,
                shift: true,
              ): () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const NewSqlIntent());
              },

              // Open SQL File: Ctrl+O / Cmd+O
              const material.SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ): () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const OpenSqlIntent());
              },
              const material.SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
              ): () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const OpenSqlIntent());
              },

              // Save SQL File: Ctrl+S / Cmd+S
              const material.SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
              ): () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const SaveSqlIntent());
              },
              const material.SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
              ): () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const SaveSqlIntent());
              },

              // Toggle Left Sidebar: Ctrl+B / Cmd+B
              const material.SingleActivator(
                LogicalKeyboardKey.keyB,
                control: true,
              ): () => _splitKey.currentState?.toggleSidebar(),
              const material.SingleActivator(
                LogicalKeyboardKey.keyB,
                meta: true,
              ): () => _splitKey.currentState?.toggleSidebar(),

              const material.SingleActivator(
                LogicalKeyboardKey.keyP,
                control: true,
              ): () => unawaited(showCommandPalette(context)),
              const material.SingleActivator(
                LogicalKeyboardKey.keyP,
                meta: true,
              ): () => unawaited(showCommandPalette(context)),
              const material.SingleActivator(
                LogicalKeyboardKey.keyK,
                control: true,
              ): () => _openQuickSwitcher(),
              const material.SingleActivator(
                LogicalKeyboardKey.keyK,
                meta: true,
              ): () => _openQuickSwitcher(),

              // Welcome Tour & Tutorial: F1 / Cmd+Shift+H / Ctrl+Shift+H
              const material.SingleActivator(
                LogicalKeyboardKey.f1,
              ): () => _onOpenWelcomeTour(),
              const material.SingleActivator(
                LogicalKeyboardKey.keyH,
                meta: true,
                shift: true,
              ): () => _onOpenWelcomeTour(),
              const material.SingleActivator(
                LogicalKeyboardKey.keyH,
                control: true,
                shift: true,
              ): () => _onOpenWelcomeTour(),

              // Return to Start / Home Screen: Cmd+Shift+0 / Ctrl+Shift+0
              const material.SingleActivator(
                LogicalKeyboardKey.digit0,
                meta: true,
                shift: true,
              ): _onGoHome,
              const material.SingleActivator(
                LogicalKeyboardKey.digit0,
                control: true,
                shift: true,
              ): _onGoHome,
            },
            child: QueryaPlatformMenuBar(
              onNewConnection: () =>
                  unawaited(_onNewDatabaseConnectionFromMenu()),
              onNewQueryTab: () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const NewSqlIntent());
              },
              onOpenSqlScript: () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const OpenSqlIntent());
              },
              onSaveQuery: () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const SaveSqlIntent());
              },
              onExecuteQuery: () =>
                  SqlEditorCommandBridge.instance.invokeExecute(),
              onToggleSidebar: () => _splitKey.currentState?.toggleSidebar(),
              onOpenPreferences: () => showPreferencesDialog(context),
              onOpenWelcomeTour: () => _onOpenWelcomeTour(),
              onGoHome: _onGoHome,
              child: SqlEditorGlobalActions(
                activeConnection: workspace.activeConnection,
                onOpenSqlWorkspace: _openSqlWorkspaceForConnection,
                child: material.Scaffold(
                backgroundColor: wb.canvas,
                body: WindowBorder(
                color: wb.borderSubtle.withValues(alpha: 0.35),
                width: 1,
                child: Column(
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: _isSidebarVisible,
                      builder: (context, isSidebarVisible, _) {
                        return QueryaWindowTitleBar(
                          onNewDatabaseConnection:
                              _onNewDatabaseConnectionFromMenu,
                          onNewDatabaseConnectionFromUrl:
                              _onNewDatabaseConnectionFromUrl,
                          activeConnection: workspace.activeConnection,
                          isReadOnly: workspace.isReadOnly,
                          isSidebarVisible: isSidebarVisible,
                          onToggleSidebar: () =>
                              _splitKey.currentState?.toggleSidebar(),
                          onOpenWelcomeTour: _onOpenWelcomeTour,
                          onGoHome: _onGoHome,
                          onReadOnlyChanged: () => unawaited(_toggleReadOnly()),
                          onConnect: () {
                            final active = workspace.activeConnection;
                            if (active != null && active.id != null) {
                              _connectionsPanelKey.currentState
                                  ?.connect(active.id!);
                            }
                          },
                          onReconnect: () {
                            final active = workspace.activeConnection;
                            if (active != null) {
                              _connectionsPanelKey.currentState
                                  ?.reconnect(active);
                            }
                          },
                          onDisconnect: () {
                            final active = workspace.activeConnection;
                            if (active != null) {
                              _connectionsPanelKey.currentState
                                  ?.disconnect(active);
                            }
                          },
                          onDisconnectAll: () {
                            _connectionsPanelKey.currentState?.disconnectAll();
                          },
                          onDisconnectOthers: () {
                            final active = workspace.activeConnection;
                            if (active != null) {
                              _connectionsPanelKey.currentState
                                  ?.disconnectOthers(active);
                            }
                          },
                        );
                      },
                    ),
                    QueryaDivider(
                        height: 1,
                        color: wb.borderSubtle.withValues(alpha: 0.22)),
                    Expanded(
                      child: MainContentSplit(
                        key: _splitKey,
                        connectionsPanelKey: _connectionsPanelKey,
                        workspace: _workspace,
                        onSidebarVisibilityChanged: (v) =>
                            _isSidebarVisible.value = v,
                        onConnectionSelected: _onConnectionSelected,
                        onPostgresObjectSelected: _onPostgresObjectSelected,
                        onMysqlObjectSelected: _onMysqlObjectSelected,
                        onSqliteObjectSelected: _onSqliteObjectSelected,
                        onExtensionObjectSelected: _onExtensionObjectSelected,
                        onRedisDatabaseSelected: _onRedisDatabaseSelected,
                        onMongoDBDatabaseSelected: _onMongoDBDatabaseSelected,
                        onMongoCollectionSelected: _onMongoCollectionSelected,
                        onPostgresOpenSqlWorkspace: _onPostgresOpenSqlWorkspace,
                        onMysqlOpenSqlWorkspace: _onMysqlOpenSqlWorkspace,
                        onSqliteOpenSqlWorkspace: _onSqliteOpenSqlWorkspace,
                        onRequestNewConnection: _openNewConnectionFromHero,
                        onRequestNewConnectionFromUrl:
                            _onNewDatabaseConnectionFromUrl,
                        onRequestOpenSqlite: _openSqliteFromHero,
                        onRequestLaunchDemo: _onLaunchDemoPlayground,
                        onRequestOpenTour: _onOpenWelcomeTour,
                        onOpenConnection: _onConnectionSelected,
                        initialMongoCollection: _pendingMongoCollection,
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _isSidebarVisible,
                      builder: (context, isSidebarVisible, _) {
                        return ListenableBuilder(
                          listenable: QueryaShellStatus.instance,
                          builder: (context, _) {
                            final status = QueryaShellStatus.instance;
                            return QueryaStatusBar(
                              activeConnection: workspace.activeConnection,
                              isReadOnly: workspace.isReadOnly,
                              isSidebarVisible: isSidebarVisible,
                              onToggleSidebar: () =>
                                  _splitKey.currentState?.toggleSidebar(),
                              onOpenPreferences: () =>
                                  showPreferencesDialog(context),
                              isBusy: status.isBusy,
                              statusMessage: status.statusMessage,
                              rowCount: status.rowCount,
                              columnCount: status.columnCount,
                              lastQueryDuration: status.lastQueryDuration,
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            ),
          ),
        ),
        ),
      );
    },
  );
}
}
