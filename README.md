# Querya Desktop

A lightweight desktop client for SQL and NoSQL databases. Connect to PostgreSQL, MySQL, Redis, and MongoDB from a single app with a clean, dark UI inspired by tools like pgAdmin.

## What it is

- **Cross-platform:** Windows, Linux, macOS (Flutter desktop).
- **Multi-database:** PostgreSQL, MySQL, Redis, MongoDB (more can be added).
- **UI:** Custom window (no system title bar), resizable left panel (connection tree) and bottom split (query editor / results), dark theme, [shadcn_flutter](https://pub.dev/packages/shadcn_flutter) components.
- **Flow:** Right-click “Servers” → “New connection” → pick database type → (future: connection form and query execution).

## Tech stack

- **Flutter** (Dart) with desktop support  
- **shadcn_flutter** for UI (buttons, inputs, theme)  
- **bitsdojo_window** for custom frame and window sizing  

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable) with desktop enabled:
  ```bash
  flutter config --enable-linux-desktop   # or windows, macos
  ```

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
| `lib/features/main_screen/` | Main layout, connections panel, new connection dialog, query/results tabs |
| `lib/shared/widgets/` | Shared UI (shadcn re-exports) |
| `lib/core/theme/` | Dark theme and colors |
| `assets/images/` | Database type icons (PostgreSQL, MySQL, Redis, MongoDB) |
| `linux/`, `windows/`, `macos/` | Native runners (custom frame on Linux/Windows) |

## License

See repository license if present.
