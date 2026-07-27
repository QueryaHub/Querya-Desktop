# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.11] - 2026-07-27

Universal UI standard for drivers/extensions, shell UX hardening, Fluid QueryaMotion morphing, virtual grid/pool reliability, performance follow-ups, and dual-channel packaging (portable + installable).

### Added

- **SDUI / extension RPC expand (#323)** — `getCapabilities`, `getServerStats`, `getObjectMetadata`, and `cancelQuery` on the plugin bridge for richer driver UIs.
- **ExtensionTableView (#324)** — table toolbar, custom SQL filter, and async row-count for sandboxed drivers.
- **Universal data export (#326)** — CSV, JSON, Markdown, and SQL dump from ResultsTab / table toolbars.
- **MySQL / SQLite UI parity (#325)** — align workspace chrome and flows with the Obsidian UI standard.
- **Shell UX (#339)** — semantic palette, shared toast, keyboard-operable tab strip, empty-workspace hero + recent connections, resizable connections sidebar, shared dialogs/widgets.
- **Fluid QueryaMotion (#342)** — spring primitives, workspace empty↔connected morph, sliding tab indicator, hero/recent stagger, ResultsTab mode morph, dialog/dropdown fade-slide, theme morph gated by motion level, split drag-end settle + motion guardrails.
- **Perf follow-ups (#356 / #357–#366)** — isolate tab-strip rebuilds; SwitchingBody/CrossFade `RepaintBoundary` + `TickerMode`; static dialog blur; vertical-split paint isolation; ticker-gated stats polling; badge pulse lifecycle; ResultsTab morph paint scope; document theme morph cost, stagger/badge duration constants, and Linux query-only refresh_rate.
- **Portable + installable packaging (#379–#385)** — portable zip channel documented on Releases; Linux AppImage and `.deb`; Windows Inno Setup (`*-windows-setup.exe`); `QUERYA_PORTABLE` / `QueryaData/` portable profile root; one-shot migration from legacy `com.example.*` support paths; updater prefers release asset matching install context (zip vs AppImage vs setup).

### Fixed

- **Virtual result grid (#331)** — synchronize column width recalculation in `VirtualResultGrid`.
- **Connection pools (#332)** — eviction and exception wrapping in SQLite and MySQL pools.
- **Query timeout (#333)** — force-close connection on `TimeoutException`.
- **Large result mapping (#334)** — optimize SQL result set mapping and DDL rendering; RPC parse on compute isolate where applicable.
- **Sidebar width persist (#354)** — keyboard/semantics resize + dispose flush; dropdown exit delay for fade-slide.
- **Linux build (#394)** — silence Clang `-Wdeprecated-literal-operator` from `flutter_secure_storage_linux` 9.x.
- **Tests** — skip legacy profile migration during `flutter test` runs (isolated temp dirs).

### Changed

- **Bundle / application IDs (#385)** — `com.queryahub.querya_desktop` (Linux), `com.queryahub.queryaDesktop` (macOS), `QueryaHub` / `Querya Desktop` (Windows).
- **Dialog sizing (#394)** — larger connection forms, database picker, and Preferences dialog via `WindowLayout` constants.
- **CI / release hygiene** — merge `main` into `dev` (#346); Release workflow publishes portable zips plus installable AppImage, `.deb`, and Windows setup; `SHA256SUMS.txt` covers all artifacts — see [packaging.md](docs/packaging.md) and [tags-and-releases.md](docs/tags-and-releases.md).

## [0.4.10] - 2026-07-11

Sandboxed extension runtime, SDUI, and first end-to-end external database drivers (Registration + Activation), plus in-app updates and connection reliability fixes.

### Added

- **Extension sandbox runtime (Block E, #300–#305)** — parse `sandbox` capabilities from manifests; launch plugins via `SandboxProcessRunner` (bwrap / sandbox-exec / Windows soft-start); Zero-Trust `system.injectCredentials` over Stdio; watchdog + auto-recovery; stderr sanitization, rotating logs, and security audit; Level-1 embedded runtime stubs and lifted preview gate for policy-compliant `process` drivers.
- **Plugin RPC bridge (Block C, #312)** — `PluginRpcBridge` over NDJSON JSON-RPC (`system.handshake` / `ping` / `shutdown`, `db.connect`).
- **SDUI builders (#314)** — `SduiFormBuilder` and `SduiTreeBuilder` render connection forms and schema trees from extension JSON schemas (`key` / `boolean` aliases supported).
- **Local extension install (#316)** — install `.zip` / `.qext` packages from Preferences and Extension Manager with the same SandboxPolicy checks as the Marketplace.
- **Driver Registration + Activation (#318 / #319)** — parse `contributions.drivers` / `capabilities`; list installed drivers in New Connection and Driver Manager; SDUI connection form; `ExtensionDriverSession` for connect + schema tree; SQL workspace / table view for sandboxed drivers; Docker ClickHouse service for local testing.
- **In-app updates (#280–#282)** — updater service, Check for Updates UI / badge / startup settings, and platform installer helpers.
- **SSL certificate pickers for MySQL, MongoDB, and Redis (#278)** — optional client certificate paths on those connection forms.
- **SQLite in Driver Manager (#270)** — built-in SQLite listed alongside other Dart drivers.

### Fixed

- **Secrets / shutdown / reliability** — atomic LocalDb + secure-store updates (#276); disconnect SQLite on app shutdown (#271); log remaining silent catches in database drivers (#272); harden MySQL custom SELECT validation (#274); stream large CSV exports on an isolate (#277).
- **UI / menus** — disabled Run (F5) when no SQL-capable connection (#266); coming-soon placeholders for unfinished workspace tabs (#267); global File → New/Open/Save SQL for active SQL editors (#268).
- **Marketplace** — database drivers without a valid process sandbox stay preview-only listings (#269).
- **Sandbox launch** — mark driver binaries executable after zip install; fall back when bubblewrap user namespaces are unavailable.

## [0.4.9] - 2026-07-10

PostgreSQL connection reliability and TLS improvements, plus menu and URI import polish.

### Added

- **Connection → New Connection from URL (#228)** — create a connection by pasting a database URI for PostgreSQL, MySQL, MongoDB, Redis, or SQLite. The URL is parsed, validated, and saved to `LocalDb`.
- **Help → About & Documentation (#229)** — added an About dialog showing the app version, MIT license, and repository link; the Documentation menu item opens the project docs in the browser.
- **PostgreSQL SSL certificate file pickers (#260)** — added optional file pickers for `sslrootcert`, `sslcert`, and `sslkey` in the PostgreSQL connection form. Paths are merged into the connection URI or used to generate a URI when in host/port mode.

### Fixed

- **PostgreSQL URL parser / SSL (#249, #253, #254, #257, #258)** — validate `sslmode` (reject `prefer` and unknown values), correctly map `useSSL` for `disable`/`require`/`verify-ca`/`verify-full`, use driver default ports when omitted, and preserve display host/port for URI-only connections.
- **PostgreSQL connection error reporting (#250, #251, #252)** — `testConnection` now returns the underlying error message, the form shows the real failure reason, and the connection tree displays the full exception text instead of a generic "Error" label.
- **PostgreSQL connection error typing (#256, #259)** — `connect()` throws `PostgresConnectionException` with the original cause and stack trace; the pool wraps unexpected factory errors in the same typed exception.

## [0.4.8] - 2026-07-08

### Fixed

- **SQLite / RETURNING clause support (#243)** — support RETURNING clauses for INSERT, UPDATE, and DELETE DML queries in the SQLite database driver, returning the resulting rows to the client.
- **Security / MySQL Injection Fix (#241)** — replaced manual escaping and string concatenation in schema introspection methods (`listViews`, `listColumnNames`, `listTables`) in the MySQL database driver with parameterized queries using parameter binding.

## [0.4.7-a] - 2026-06-22

### Added

- **Connection Invalidate/Reconnect** — added Invalidate/Reconnect action in the application menu and window title bar.
- **Connection Read-only Mode** — added Read-only mode for PostgreSQL and SQLite database connections to prevent write operations (displays a lock icon in the workspace).
- **Connection Lifecycle Management** — added Connect and Disconnect menu items and corresponding title bar controls.

### Documentation

- Added comprehensive setup guides for SQLite, Read-only connection mode, and connection lifecycle controls in the English user guide and Obsidian Russian notes.

## [0.4.7] - 2026-06-21

Local extension discovery and manifest foundation release. Git tag **`0.4.7`**.

### Added

- **Extension models (EXT-1)** — data models `ExtensionManifest` and `ExtensionType` to parse `manifest.json`.
- **Local scanner (EXT-2)** — `LocalExtensionRegistry` scans `~/.querya/extensions/` to find and load extension manifests.
- **Theme migration (EXT-3)** — migrated legacy custom themes to the new unified extension package format.
- **Unit tests (EXT-4)** — unit tests for manifest parsing, directory scanning, and registry cache logic.

### Fixed

- **Theme importing security** — resolved concurrent import TOCTOU filesystem races and theme ID collisions during migration, and cleaned up deprecated legacy import code.
- **Appearance Settings test** — resolved the preferences appearance section widget test failure by mocking the extensions directory.

## [0.4.6-a] - 2026-06-18

### Changed

- **UI / Sidebar** — implemented collapsible dropdown tree nodes for tables and views in SQLite and MySQL connections.

## [0.4.6] - 2026-06-18

SQLite database connector release. Git tag **`0.4.6`**.

### Added

- **SQLite connection driver (SQL-S1)** — support local SQLite database files opening, closing, and queries via FFI.
- **Catalog schema resolver (SQL-S2)** — automatic tables, views, indexes, and column schema detection.
- **Connection dialog (SQL-S3)** — SQLite connection form with native file-picking (`file_selector`) and read-only toggle.
- **Connections sidebar (SQL-S4)** — integrated SQLite nodes with expand/collapse hierarchy under Connections.
- **SQL Workspace editor & Paginated table (SQL-S5)** — SQLite query workspace supporting history lookups, statement executions, and paginated data grid browser.
- **Docker test database** — added `sqlite-seed` container to `docker-compose.yml` to automatically generate a local `querya.db` file with mock data alongside other test databases.

### Fixed

- **UI / Accessibility** — fixed text clipping in workspace toolbars and settings when increasing the interface scale (e.g., 150%). Replaced hardcoded heights with `minHeight` constraints and dynamically scaled label widths.
- **UI / Stability** — resolved `A RenderAnimatedSize was mutated in its own performLayout implementation` crash during split pane dragging by removing redundant `LayoutBuilder` wrappers.
- **Linting** — resolved `flutter analyze` warnings for deprecated Shadcn legacy colors and flow control structures.

## [0.4.4] - 2026-06-16

UI motion polish, high refresh rate, performance fixes, and security improvements release. Git tag **`0.4.4`**.

### Added

- **Motion tokens core (UI-A1)** — `QueryaMotion` core durations and curves, providing a single source of truth for all animations.
- **Token adoption (UI-A2)** — replace magic/scattered duration and curve literals with standardized tokens.
- **Smoother transitions (UI-A3)** — menu/dropdown enter fade+scale, dialog blur/scale retune, tree height animation (`QueryaAnimatedExpand`), and workspace tab content cross-fade (`QueryaCrossFadeStack`).
- **High refresh rate (UI-A4)** — unlock native ProMotion on macOS 14+, active Hz logging at startup, and FPS/Hz debug overlay.
- **Reduced motion setting (UI-A5)** — Preferences toggle (`Full` / `Reduced` / `Off`) and automatic OS reduced-motion configuration matching.
- **Docs & performance checks (UI-A6)** — per-OS measured refresh-rate verification table, DevTools performance checklists, and release QA items.
- **SQLite Database Support Plan (0.4.5)** — design and implementation roadmap for local SQLite file connector support.

### Fixed

- **Memory: SQL Result Capping (Issue #184)** — PostgreSQL and MySQL query execution now limits client memory usage by applying query LIMITs database-side and streaming rows using `rowsStream` (breaking early).
- **Performance: MongoDB Client-side Pagination (Issue #185)** — uses `SelectorBuilder` skip/limit operators on the server instead of client-side stream buffering.
- **Performance: N+1 secure storage lookups (Issue #186)** — parallelizes connection secrets hydration on startup.
- **Performance: Redis Key Scanning round-trips (Issue #187)** — runs type and TTL lookups concurrently for key batches.
- **Security: Theme Remote Installation SSRF (Issue #183)** — parses and filters IPv6 and private/loopback/multicast/mapped hosts using `InternetAddress.tryParse`.
- **UX: Focus leak on QueryaCrossFadeStack** — wraps inactive children in `ExcludeFocus` and `ExcludeSemantics` to prevent tab-indexing into off-screen tabs.

## [0.4.3] - 2026-06-15

Theme follow-ups release (TP-F1–TP-F4, GitHub issues **#159–#163**). Git tag **`0.4.3`**.

### Added

- **Theme folder watcher (TP-F1)** — debounced `Directory.watch` on `{appSupport}/themes/` auto-refreshes the registry when files are added, removed, or renamed.
- **Marketplace metadata (TP-F2)** — optional manifest fields (`homepage`, `license`, `preview`, `tags`); theme picker shows author/tags; `ExtensionManifest` stub in `lib/core/market/` for future Explore UI.
- **Visual theme editor (TP-F3)** — Preferences section to tweak workbench colors with live preview and export `querya.theme.v1` JSON.
- **Remote theme install (TP-F4)** — **Install from URL…** (HTTPS-only, public hosts, optional SHA-256); `ThemeRemoteInstallService` with checksum verify before import.
- **Docs / QA** — remote install section in [theme-import.md](docs/theme-import.md); 0.4.3 items in [release-checklist.md](docs/release-checklist.md).
- **Tests** — file watcher, remote install policy/service, theme editor and metadata coverage.

## [0.4.2] - 2026-06-14

Custom theme registry release (parser epic TP-01–TP-30, GitHub issues **#96–#125**). Git tag **`0.4.2`**.

### Added

- **Custom theme registry** — scan `{appSupport}/themes/` for `querya.theme.v1` and VS Code JSON/JSONC; **Theme** picker with search, hover preview, **Refresh themes**, and **Open themes folder** (Preferences → Appearance).
- **Built-in bundled themes** — **Querya Cyberpunk Neon** from `assets/themes/` (no manual install).
- **Theme import** — **Import theme…** copies into the user themes directory with content-hash and id deduplication; selection persists across restarts.
- **Startup safety** — missing or broken selected theme falls back to Querya Dark with a Preferences error; saved theme id is kept until the user picks another theme.
- **Window chrome** — title bar and window controls follow active `QueryaThemeScope` workbench tokens.
- **Docs / QA** — [theme-custom-json.md](docs/theme-custom-json.md), updated [theme-import.md](docs/theme-import.md), custom-theme section in [release-checklist.md](docs/release-checklist.md).
- **Tests** — registry/parser/controller coverage, 60-theme picker performance guard, end-to-end import flow (`theme_import_flow_test.dart`).

## [0.4.1] - 2026-06-13

Performance and UX release ([#93](https://github.com/QueryaHub/Querya-Desktop/issues/93)). Git tag **`0.4.1`**.

### Added

- **MySQL server stats** — full dashboard (connections, queries, network, databases table) via `SHOW GLOBAL STATUS` / `information_schema`.
- **Virtual SQL result grid** — `VirtualResultGrid` with fixed column widths, cell copy, and `RepaintBoundary` instead of a materialized `Table`.
- **Lazy connection tree** — `lazyConnectionTreeList` / `ListView.builder` for large PostgreSQL and MySQL object lists; `ValueKey` on leaf rows.
- **Vertical split pane** — `ValueNotifier`-driven splitter drag without rebuilding entire workspace panels.
- **Docker dev stack** — `docker/` compose with PostgreSQL, MySQL, MongoDB, Redis and seed data for local testing.
- **`deep_collection_equals`** — shared snapshot diff helper for stats polling.

### Changed

- **UI scale preview** — decoupled from app-wide theme rebuilds; scale commits only on slider release.
- **Syntax highlighting** — debounced updates, worker isolate for all buffer sizes, highlighter pair cache by theme key.
- **Stats dashboards** — Redis, MongoDB, and PostgreSQL skip `setState` when polled data is unchanged; Redis/Mongo layouts redesigned; MySQL replaces version-only stub.
- **Connection forms** — `FormValidityNotifier` narrows rebuild scope to action buttons.
- **SQL workspace settings** — `SqlWorkspaceSettingsRevision` so theme/scale changes do not reload SQL tabs.
- **Connections panel** — rebuilds only when selected connection id changes.
- **MySQL results** — row string conversion moved to a worker isolate (`mysql_result_utils`).
- **Redis key editor** — virtualized hash/list/set/zset member lists.
- **Mongo documents** — lazy pretty-JSON cache; document cards without hover `setState`.
- **Explorer list rows** — Redis/Mongo database/key/collection rows use `InkWell` hover instead of hover `setState`.
- **QueryaDropdown** — caches menu children; ellipsizes trigger label in fixed-width layouts.

### Fixed

- **Connection menu** — new connection form opens after picking type from the menu ([#93](https://github.com/QueryaHub/Querya-Desktop/issues/93) follow-up).
- **Stats UI overflow** — Redis, MongoDB, and PostgreSQL stats cards no longer overflow in debug/profile layouts.
- **Redis TTL dialog** — disposes `TextEditingController` on close.

## [0.4.0] - 2026-05-28

Theme system milestone (epic #37). Git tag **`0.4.0`** — use this release for binaries; earlier tag `0.3.0` was a pre-PR snapshot.

### Added

- **Theme system** — runtime dark/light/system modes, **Querya Light** preset, optional **Animate theme changes** in Preferences.
- **VS Code themes** — import `.json` / `.jsonc` (`colors` + `tokenColors`); user color overrides; persisted imported theme.
- **Syntax highlighting** — SQL and JSON in `QueryaCodeEditor` via `syntax_highlight`; `tokenColors` mapped to TextMate scopes; isolate highlight for large buffers.
- **Editor** — `QueryaCodeEditor` abstraction, `SqlEditorChrome` from theme tokens, `QueryaThemeScope` for workbench/editor tokens.
- **Samples** — `themes/samples/cyberpunk-neon.json` (+ JSONC) for manual import testing.
- **Docs** — [docs/theme.md](docs/theme.md), [docs/theme-import.md](docs/theme-import.md), [docs/archive/editor-spike-report.md](docs/archive/editor-spike-report.md), [docs/archive/code-forge-evaluation.md](docs/archive/code-forge-evaluation.md).

### Changed

- **Workbench UI** — P0 surfaces (sidebar, SQL chrome, empty hero, main shell) use design tokens instead of hardcoded `QueryaColors`.
- **Preferences** — Appearance section (theme mode, preset, import, animation); Material `DropdownMenu` for stable menus in scrollable dialogs.
- **Imported themes** — `mutedForeground` clamped for readable helper text when VS Code sidebar colors are low-contrast.

### Fixed

- **Preferences (dark / imported themes)** — readable labels and dropdown text via `materialTheme` + `popoverForeground` hints.
- **Preferences dropdown** — Color preset menu no longer stretches full screen (`expandedInsets` instead of `width: infinity`).
- **Dialogs / SQL editor** — `QueryaThemeScope` on `ShadcnApp.builder` so overlays (Preferences, SQL editor) resolve theme tokens.

## [0.2.0] - 2026-04-24

### Added

- **SQL result export** — from the PostgreSQL / MySQL **Data Output** grid: **Copy as CSV**, **Save as CSV…**, **Copy as JSON**, **Save as JSON…** (native save dialog via **`file_selector`** on Linux, macOS, and Windows).
- **SQL query history** — successful statements are stored in local **SQLite** (per saved connection and database bucket); **History** in the SQL toolbar opens a recall dialog; **Edit → Preferences** adds **Query history limit** (25–500 entries, oldest trimmed automatically).
- **PostgreSQL** — `postgres_object_workspace.dart` builds object views from the sidebar tree (logic moved out of `workspace_panel` for clarity).
- **Documentation** — contributing notes, product **roadmap**, macOS signing track; README structure refresh.
- **Tests** — MySQL SQL workspace home, driver manager, and preferences dialog widget coverage; storage tests for query history and export encoding.

### Changed

- **Connections sidebar** — `connections_panel` split into **part libraries** for easier maintenance (behavior preserved).
- **CI / release** — Flutter toolchain pinned to **3.41.6** for analyze, tests, and release builds.
- **PostgreSQL — workspace** — a selected table, view, or other object opens **full width**; **Server** / **SQL** tabs show only when no object is selected for that connection. **Open in SQL** still seeds the editor from the current browse context; the SQL toolbar **DB:** line follows the tree catalog when a seed is applied.
- **PostgreSQL** — shared browse query helper (`postgresBrowseSelectSql`) and default page size (`kPostgresBrowseDefaultRowLimit`) align the data grid with the SQL editor template.
- **MySQL** — comparing the table browse query to the mini-editor SQL ignores trailing semicolons and normalizes whitespace; hint text clarifies that **Run** reloads from the server even when rows look unchanged.

### Fixed

- **PostgreSQL — Open in SQL** — the context menu seeds the editor from the **row you right-clicked** (database, schema, table/view/matview name). Previously the app used only the last **left-click** selection, so the query could target the wrong table.

## [0.1.3] - 2026-04-25

### Added

- **Performance** — narrower workspace rebuilds via `ValueNotifier` / `ValueListenableBuilder` on the main screen; `RepaintBoundary` around connections and workspace; folder expansion uses local state so the whole sidebar does not rebuild on every toggle.
- **Lists** — virtualized long lists for MongoDB documents/collections, Redis keys, and PostgreSQL browser views (indexes, triggers, types, extensions, foreign data).
- **Tests** — `MainScreenWorkspaceState`, `showAppDialog`, `RedisKeysView` (with `RedisConnectionTestFake`), and expanded connections panel folder collapse/expand coverage.
- **Docs** — `docs/perf-baseline.md` (Flutter DevTools checklist for regression comparison).

### Changed

- **Dialogs** — slightly shorter transition and lower blur sigma in `showAppDialog` to reduce GPU load on modest hardware.
- **Connections tree** — slightly shorter chevron rotation animation.

### Fixed

- **PostgreSQL server dashboard** — removed fixed-height cards and chip layout that caused vertical overflow (yellow/black debug stripes) on the stats view.

## [0.1.2] - 2026-04-24

### Changed

- **Releases** — tag push no longer fails when git tag and `pubspec` semver differ after auto version-bump on `main` (warning only; artifact names follow `pubspec`).

## [0.1.1] - 2026-04-24

### Changed

- **Releases** — pushing a version **git tag** matching `pubspec` (e.g. `0.1.1` after `version: 0.1.1+1`) runs the **Release** workflow: Windows/Linux zips, `SHA256SUMS.txt`, and a GitHub Release (no `v` prefix in tag or artifact names). Manual **Actions → Release** still works.

## [0.1.0] - 2026-04-24

### Added

- **Preferences** — **Edit → Preferences** dialog: global SQL statement timeout (shared dropdown), max result rows presets, editor font size, and `AppSettingsRevision` so open SQL workspaces refresh when settings change.
- **Security** — connection passwords and sensitive connection material stored via **`flutter_secure_storage`** (OS keychain/credential store); local SQLite schema migration for non-secret fields only (see `docs/security.md`).
- **MIT LICENSE** at repository root.
- **Documentation** — `docs/security.md`, `docs/user-guide.md`, `docs/release-checklist.md`; release/tag process updates in `docs/tags-and-releases.md`.
- **Linux** — `run_linux.sh` checks for `libsecret` via `pkg-config` before `flutter run`.
- **UI** — empty-workspace hints (menu path to new connection and docs); **Connection → New Database Connection** wired in the menu.
- **Tests** — coverage for `AppSettingsRevision`, `SqlStatementTimeoutDropdown`, and `QueryEditorTab` font size behavior.

### Changed

- **Connections / drivers** — removed JDBC driver download UI and related storage/URL helpers; MySQL/Postgres use Dart clients only.
- **CI / release** — Linux runners install **`libsecret-1-dev`**; release workflow aligned with version tags from `pubspec`.
- **Linux build** — CMake install prefix forced so the Flutter bundle installs under **`build/`** instead of system paths such as `/usr/local`.

### Fixed

- Linux desktop build/install layout no longer targets `/usr/local` when building the app bundle.

[0.2.0]: https://github.com/QueryaHub/Querya-Desktop/compare/0.1.3...0.2.0
[0.1.3]: https://github.com/QueryaHub/Querya-Desktop/compare/0.1.2...0.1.3
[0.1.2]: https://github.com/QueryaHub/Querya-Desktop/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/QueryaHub/Querya-Desktop/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/QueryaHub/Querya-Desktop/compare/0.0.1...0.1.0
