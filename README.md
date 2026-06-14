<div align="center">

# Querya Desktop

**A lightweight, cross-platform desktop client for SQL and NoSQL databases.**

Connect to PostgreSQL, MySQL/MariaDB, Redis, and MongoDB from a single app with
a clean, dark UI inspired by tools like pgAdmin.

[![CI](https://github.com/QueryaHub/Querya-Desktop/actions/workflows/ci.yml/badge.svg)](https://github.com/QueryaHub/Querya-Desktop/actions/workflows/ci.yml)
[![Release](https://github.com/QueryaHub/Querya-Desktop/actions/workflows/release.yml/badge.svg)](https://github.com/QueryaHub/Querya-Desktop/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-Desktop-02569B?logo=flutter)](https://flutter.dev)
[![Platforms](https://img.shields.io/badge/Platforms-Linux%20%7C%20Windows%20%7C%20macOS-555)](#)

</div>

---

## Highlights

- **Multi-database** — PostgreSQL, MySQL/MariaDB, Redis, and MongoDB, with
  built-in Dart drivers (no JDBC JARs to download).
- **Cross-platform** — Linux, Windows, and macOS from one Flutter codebase.
- **SQL workspace** — query editor with syntax highlighting, configurable
  statement timeouts, query history, and CSV/JSON export.
- **Object browsing** — connection tree with databases, tables, views, and
  server stats.
- **Themeable** — dark/light/system, **VS Code theme import**, custom `querya.theme.v1` registry, and bundled themes (0.4.2).
- **Scalable UI** — global interface scaling for high-DPI and accessibility.
- **Secure by default** — passwords and connection strings live in the OS secure
  store, never in plaintext.

## Screenshots

> _Add screenshots/GIFs to `docs/assets/` and reference them here._

## Quick start

```bash
# 1. Enable Flutter desktop for your platform
flutter config --enable-linux-desktop      # or --enable-windows-desktop / --enable-macos-desktop

# 2. Fetch dependencies
flutter pub get

# 3. Run
flutter run -d linux                        # or windows / macos
```

Linux builds also need keyring headers (`libsecret-1-dev` on Debian/Ubuntu).
See **[Getting started](docs/getting-started.md)** for the full setup, including
prerequisites, release builds, and your first connection.

## Tech stack

- **[Flutter](https://flutter.dev)** (Dart) with desktop support.
- **[shadcn_flutter](https://pub.dev/packages/shadcn_flutter)** for UI components and theming.
- **[bitsdojo_window](https://pub.dev/packages/bitsdojo_window)** for the custom window frame.
- Built-in Dart drivers: `postgres`, `mysql_client`, `redis`, `mongo_dart`.

## Project structure

| Path | Description |
|------|-------------|
| `lib/main.dart` | App entry, window setup. |
| `lib/app/` | App shell and theme wiring. |
| `lib/core/` | Database clients, storage, theme, layout, editor helpers. |
| `lib/features/` | Feature modules (main screen, connections, per-engine UI, settings). |
| `lib/shared/` | Reusable widgets shared across features. |
| `assets/` | Database type icons and other bundled assets. |
| `linux/`, `windows/`, `macos/` | Native runners. |
| `third_party/` | Vendored components (e.g. `shadcn_flutter`), under their own licenses. |

For a deeper map of modules and their responsibilities, see
**[Architecture](docs/architecture.md)**.

## Documentation

Full documentation lives in **[`docs/`](docs/README.md)**:

- **[Getting started](docs/getting-started.md)** — install and first run.
- **[User guide](docs/user-guide.md)** — connections, preferences, drivers.
- **[Architecture](docs/architecture.md)** — codebase layout.
- **[Security](docs/security.md)** — local data and secrets.
- **[Theme system](docs/theme.md)** · **[Theme import](docs/theme-import.md)**.
- **[Roadmap](docs/roadmap.md)** · **[Releases](docs/tags-and-releases.md)**.

## Contributing

Contributions are welcome. Please read **[CONTRIBUTING.md](CONTRIBUTING.md)** for
the workflow, CI expectations, and the pre-PR checklist, and see the
[Changelog](CHANGELOG.md) for release history.

## License

[MIT](LICENSE). Third-party components (e.g. vendored UI under `third_party/`)
retain their own licenses.
