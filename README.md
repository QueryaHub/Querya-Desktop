# Querya Desktop

A lightweight desktop client for SQL and NoSQL databases. Connect to PostgreSQL, MySQL, Redis, and MongoDB from a single app with a clean, dark UI inspired by tools like pgAdmin.

## What it is

- **Cross-platform:** Windows, Linux, macOS (Flutter desktop).
- **Multi-database:** PostgreSQL, MySQL, Redis, MongoDB (more can be added).
- **UI:** Custom window (no system title bar), resizable left panel (connection tree) and bottom split (query editor / results), dark theme, [shadcn_flutter](https://pub.dev/packages/shadcn_flutter) components.
- **Flow:** Right-click “Servers” → “New connection” (or **Connection → New Database Connection**) → pick database type → configure and save. Metadata is stored in local SQLite; **passwords and connection strings** use the OS secure store (see [docs/security.md](docs/security.md)).

## Database drivers

- **PostgreSQL** — `postgres` (Dart); browser, SQL workspace, table/view browsing, server stats.
- **MySQL / MariaDB** — `mysql_client` (Dart); browser (databases, tables, views), SQL workspace with configurable statement timeout, paginated table/view data (read-oriented browse SQL).
- **Redis** / **MongoDB** — see connection panels and workspace.

## Tech stack

- **Flutter** (Dart) with desktop support  
- **shadcn_flutter** for UI (buttons, inputs, theme)  
- **bitsdojo_window** for custom frame and window sizing  

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable) with desktop enabled:
  ```bash
  flutter config --enable-linux-desktop   # or windows, macos
  ```
- **Linux builds** also need desktop headers used by Flutter and plugins (GTK, etc.). For `flutter_secure_storage` on Linux you typically need **`libsecret-1-dev`** (Debian/Ubuntu: `sudo apt install libsecret-1-dev`; Fedora: `libsecret-devel`). Match this to your distro’s Flutter desktop docs.

## Setup

From the project root:

```bash
flutter pub get
```

If platform folders are missing:

```bash
flutter create . --project-name querya_desktop --platforms=linux,windows,macos
flutter pub get
```

## Run

```bash
# Linux (on Wayland, use X11 to avoid Gdk warnings when the pointer leaves the window)
GDK_BACKEND=x11 flutter run -d linux

# Or
flutter run -d linux

# Windows
flutter run -d windows

# macOS
flutter run -d macos
```

Or use the helper script on Linux:

```bash
./run_linux.sh
```

## Build release

```bash
flutter build linux
flutter build windows
flutter build macos
```

## Project structure

| Path | Description |
|------|-------------|
| `lib/main.dart` | App entry, window setup (bitsdojo_window) |
| `lib/app/` | App shell and theme |
| `lib/features/main_screen/` | Main layout, workspace panel, query/results tabs |
| `lib/features/connections/` | Connection tree, new connection / folder flows, driver manager |
| `lib/features/postgresql/`, `mysql/`, `redis/`, `mongodb/` | Per-engine workspace and browser UI |
| `lib/shared/widgets/` | Shared UI (shadcn re-exports, app dialog) |
| `lib/core/` | Database clients, local storage, theme, editor helpers |
| `assets/images/` | Database type icons (PostgreSQL, MySQL, Redis, MongoDB) |
| `linux/`, `windows/`, `macos/` | Native runners (custom frame on Linux/Windows) |

## License

[MIT](LICENSE). Third-party components (e.g. vendored UI under `third_party/`) retain their own licenses.

## More documentation

- [Security / local data](docs/security.md)
- [User guide](docs/user-guide.md)
- [Releases](docs/tags-and-releases.md)
- [Release checklist](docs/release-checklist.md)
- [Contributing](CONTRIBUTING.md) (Flutter pin, tags, local analyze)
- [Roadmap](docs/roadmap.md)
