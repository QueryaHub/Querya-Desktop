# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.1]: https://github.com/QueryaHub/Querya-Desktop/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/QueryaHub/Querya-Desktop/compare/0.0.1...0.1.0
