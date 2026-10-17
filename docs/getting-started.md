# Getting started

How to build and run Querya Desktop from source.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel)
  with desktop enabled:

  ```bash
  flutter config --enable-linux-desktop   # or --enable-windows-desktop / --enable-macos-desktop
  ```

- **Linux** also needs a C++ toolchain and the desktop headers used by
  Flutter and its plugins (GTK, `libsecret` for `flutter_secure_storage`):

  ```bash
  # Debian / Ubuntu
  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev
  # Fedora
  sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel libsecret-devel
  ```

- **Flutter version.** CI builds with Flutter **3.47.1** (stable channel, see
  `.github/workflows/ci.yml`); using the same one locally avoids "works on my
  machine" drift (see [Contributing](../CONTRIBUTING.md)).

## Install

From the project root:

```bash
flutter pub get
```

The `linux/`, `windows/` and `macos/` folders are part of the repository and
hold native code of their own (window chrome, refresh-rate handling, runner
changes, icons, entitlements). **Do not run `flutter create .` here:** it would
overwrite them with the stock templates. If a platform folder looks broken,
restore it from Git (`git checkout -- linux/`) instead.

## Run

**Linux.** Use the helper script:

```bash
./run_linux.sh            # extra arguments go to `flutter run`
```

It checks that `libsecret-1` is installed (with install hints for Debian,
Fedora and Arch if it is not) and sets `GDK_BACKEND=x11`, which avoids Gdk
pointer warnings on Wayland. Plain `flutter run -d linux` also works, and runs
natively on Wayland if you prefer that.

**Other platforms:**

```bash
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
Stop with `docker compose down`. Connecting from inside the dev container, MySQL
TLS and the live-database test are in [dev-containers.md](dev-containers.md).
