# Getting started

How to build and run Querya Desktop from source.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel)
  with desktop enabled:

  ```bash
  flutter config --enable-linux-desktop   # or --enable-windows-desktop / --enable-macos-desktop
  ```

- **Linux** also needs the desktop headers used by Flutter and its plugins
  (GTK, etc.). For `flutter_secure_storage` you typically need
  **`libsecret-1-dev`**:

  ```bash
  sudo apt install libsecret-1-dev      # Debian / Ubuntu
  sudo dnf install libsecret-devel      # Fedora
  ```

  CI pins a specific stable Flutter version; matching it locally avoids
  "works on my machine" drift (see [Contributing](../CONTRIBUTING.md)).

## Install

From the project root:

```bash
flutter pub get
```

If the platform folders are missing:

```bash
flutter create . --project-name querya_desktop --platforms=linux,windows,macos
flutter pub get
```

## Run

```bash
# Linux
flutter run -d linux
# On Wayland, force X11 to avoid Gdk pointer warnings:
GDK_BACKEND=x11 flutter run -d linux
# Or use the helper script:
./run_linux.sh

# Windows
flutter run -d windows

# macOS
flutter run -d macos
```

## Build release

```bash
flutter build linux
flutter build windows
flutter build macos
```

## First connection

1. Launch the app.
2. **Connection → New Database Connection** (or right-click **Servers** in the tree).
3. Pick **PostgreSQL**, **MySQL**, **Redis**, or **MongoDB** and fill in host,
   port, and credentials.
4. Saved connections appear in the left tree.

See the [User guide](user-guide.md) for preferences, the driver manager, and
day-to-day usage, and [Security](security.md) for how credentials are stored.

## Local dev databases (optional)

The repo includes a Docker Compose stack under [`docker/`](../docker/) with
PostgreSQL, MySQL, MongoDB, Redis, ClickHouse, and SQLite seed data:

```bash
cp docker/.env.example docker/.env   # optional overrides
cd docker && docker compose up -d
```

Default credentials: user/password **`querya`**, database **`querya`**
(MongoDB auth source: **`admin`**; ClickHouse HTTP **`8123`**, native **`9000`**).
Stop with `docker compose down`.
