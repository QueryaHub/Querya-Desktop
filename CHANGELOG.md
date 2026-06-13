# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
