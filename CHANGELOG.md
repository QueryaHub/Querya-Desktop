# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-04-25

### Added

- **PostgreSQL** — `postgres_object_workspace.dart` builds object views from the sidebar tree (logic moved out of `workspace_panel` for clarity).

### Changed

- **PostgreSQL — workspace** — a selected table, view, or other object opens **full width** again; **Server** / **SQL** tabs show only when no object is selected for that connection. The SQL tab still receives a browse template when you use **Open in SQL**; the toolbar **DB:** line follows the catalog from the tree when a seed is applied.
- **PostgreSQL** — shared browse query helper (`postgresBrowseSelectSql`) and default page size (`kPostgresBrowseDefaultRowLimit`) align the data grid with the SQL editor template.
- **MySQL** — comparing the table browse query to the mini-editor SQL ignores trailing semicolons and normalizes whitespace; hint text clarifies that **Run** reloads from the server even when rows look unchanged.

### Fixed

- **PostgreSQL — Open in SQL** — the context menu seeds the editor from the **row you right-clicked** (database, schema, table/view/matview name). Previously the app used only the last **left-click** selection, so the query could target the wrong table.

## [0.2.0] - 2026-04-24

### Added

- **SQL result export** — from the PostgreSQL / MySQL **Data Output** grid: **Copy as CSV**, **Save as CSV…**, **Copy as JSON**, **Save as JSON…** (native save dialog via **`file_selector`** on Linux, macOS, and Windows).
- **SQL query history** — successful statements are stored in local **SQLite** (per saved connection and database bucket); **History** in the SQL toolbar opens a recall dialog; **Edit → Preferences** adds **Query history limit** (25–500 entries, oldest trimmed automatically).
- **Documentation** — contributing notes, product **roadmap**, macOS signing track; README structure refresh.
- **Tests** — MySQL SQL workspace home, driver manager, and preferences dialog widget coverage; storage tests for query history and export encoding.

### Changed

- **Connections sidebar** — `connections_panel` split into **part libraries** for easier maintenance (behavior preserved).
- **CI / release** — Flutter toolchain pinned to **3.41.6** for analyze, tests, and release builds.

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

[0.2.1]: https://github.com/QueryaHub/Querya-Desktop/compare/0.2.0...0.2.1
[0.2.0]: https://github.com/QueryaHub/Querya-Desktop/compare/0.1.3...0.2.0
[0.1.3]: https://github.com/QueryaHub/Querya-Desktop/compare/0.1.2...0.1.3
[0.1.2]: https://github.com/QueryaHub/Querya-Desktop/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/QueryaHub/Querya-Desktop/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/QueryaHub/Querya-Desktop/compare/0.0.1...0.1.0
