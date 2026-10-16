# Dev container and local test databases

How to open Querya Desktop in the repository's dev container, start the local
database stack, connect Querya to it and run the tests. For the plain
(non-container) workflow see [CONTRIBUTING.md](../CONTRIBUTING.md); for the
list of seeded data see the header of [`docker/docker-compose.yml`](../docker/docker-compose.yml).

## What is in the box

| File | What it does |
|------|--------------|
| [`.devcontainer/devcontainer.json`](../.devcontainer/devcontainer.json) | The dev container definition: build, features, post-create / post-start commands, forwarded ports, VS Code extensions, host requirements (4 CPUs, 8 GB). |
| [`.devcontainer/Dockerfile`](../.devcontainer/Dockerfile) | Ubuntu 24.04 with Flutter pinned to the version CI uses (`ARG FLUTTER_VERSION`, checked against `ci.yml` by a guard test), the Linux desktop toolchain (clang, cmake, ninja, GTK 3, libsecret, SQLite headers, Xvfb), `bubblewrap` for the extension sandbox tests, `socat`, and the Docker CLI with the Compose plugin. `DISPLAY` is `:99`. |
| [`scripts/dev/devcontainer_start.sh`](../scripts/dev/devcontainer_start.sh) | Runs on every start: brings the stack up, waits for the databases to be healthy, joins the stack's network and forwards `localhost:<port>` to the services. |
| [`docker/docker-compose.yml`](../docker/docker-compose.yml) | The database stack (project `querya-dev`): PostgreSQL 16, MySQL 8.4, Redis 7, MongoDB 7, ClickHouse 24.8 and a seeded SQLite file. |

The image is also published to GitHub Packages as
`ghcr.io/queryahub/querya-devcontainer` (`:latest` and `:flutter-<version>`) by the
[Dev container image](../.github/workflows/devcontainer-image.yml) workflow, rebuilt when the
Dockerfile changes and weekly for security updates. `devcontainer.json` uses it as a layer
cache (`build.cacheFrom`), so the first build pulls the toolchain layers instead of compiling
them; if the package is unreachable the build simply falls back to building from the Dockerfile.

When the container is created it runs `flutter config --enable-linux-desktop`
and `flutter pub get`; every time it starts it runs
[`scripts/dev/devcontainer_start.sh`](../scripts/dev/devcontainer_start.sh): it brings the
stack up, waits (up to `QUERYA_STACK_TIMEOUT`, 180 s) for PostgreSQL, MySQL, Redis, MongoDB
and ClickHouse to be healthy, prints which are not, and does not fail the container start
when Docker is unreachable.

## Open the dev container

### VS Code

1. Install Docker and the **Dev Containers** extension.
2. Open the repository folder and run **Dev Containers: Reopen in Container**.
3. Wait for the first build (the Flutter image is large) and for
   `flutter pub get` to finish.

### Command line

```bash
npm i -g @devcontainers/cli            # once
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

### GitHub Codespaces

Codespaces reads the same definition; `hostRequirements` ask for a 4-core / 8 GB machine.

## The database stack

The container uses **docker-outside-of-docker**: the Docker CLI inside it talks
to the **host's** daemon, so the databases are ordinary containers on your host,
next to the dev container, not inside it.

```bash
cd docker
cp .env.example .env            # optional: change host ports if they are taken
docker compose up -d            # start (the dev container does this on start)
docker compose ps               # health: wait for "healthy"
docker compose logs -f mysql    # follow one service
docker compose down             # stop, keep data
docker compose down -v          # stop and wipe volumes: init scripts run again
```

| Service | Host port | Database / user / password | Seeded with |
|---------|-----------|----------------------------|-------------|
| PostgreSQL | 5432 | `querya` / `querya` / `querya` | schema `shop.*`, database `analytics`, an all-types table |
| MySQL | 3306 | `querya` / `querya` / `querya` | `shop` tables, database `analytics`, an all-types table |
| Redis | 6379 | no auth | keys `querya:*` (seeded by `redis-seed`) |
| MongoDB | 27017 | `querya` / `querya`, auth source `admin` | collections `users`, `products`, `orders`, `types_showcase` |
| ClickHouse | 8123 (HTTP), 9000 (native) | `querya` / `querya` / `querya` | `customers`, `products`, `orders`, `order_lines`, `events`, `all_clickhouse_types` |
| SQLite | file `docker/sqlite/data/querya.db` | none | `users`, `products`, `orders` |

The init scripts run only on the first start of a volume; use `down -v` to
re-seed.

## Connect Querya to the stack

### From the host

Run Querya on the host (or `flutter run -d linux` there) and use `localhost` and
the ports above.

### From inside the dev container

The databases run on the host's daemon next to the dev container, so nothing
listens on the container's own loopback. The start script therefore does two
things for you:

- joins the container to the stack's network (`querya-dev_default`), so the
  service names `postgres`, `mysql`, `redis`, `mongo`, `clickhouse` (and
  `mysql-live`) resolve, with the container-side ports 5432, 3306, 6379, 27017,
  8123 / 9000;
- forwards `127.0.0.1:<port>` to those services with `socat`, so `localhost` and
  the usual ports work too (`psql -h localhost -U querya querya`,
  `redis-cli -h localhost ping`, the connection form with `localhost`). A port
  something already listens on is left alone.

The forwards live as long as the container does; after `docker compose down` /
`up` re-run `bash scripts/dev/devcontainer_start.sh`. If you start the
container with host networking, `localhost` already reaches the published ports
and nothing is forwarded.

On Docker Desktop `host.docker.internal` with the host ports works as well.

### Per database

| Database | In Querya |
|----------|-----------|
| PostgreSQL | Host, port 5432, database `querya`, user and password `querya`. Schemas `shop` and `analytics` show up in the tree. |
| MySQL | The user authenticates with `caching_sha2_password` (MySQL 8.4), which needs a secure connection: tick **Use SSL/TLS** in the form. Without it the connection is refused. |
| Redis | Host, port 6379, no password. |
| MongoDB | Host, port 27017, user and password `querya`, **authentication database `admin`**. A URL works too: `mongodb://querya:querya@HOST:27017/querya?authSource=admin`. |
| SQLite | Pick `docker/sqlite/data/querya.db` with *Browse…* (the file is `chmod 666`). In the container, the path is inside the workspace. |
| ClickHouse | No built-in driver: it is the target for testing **extension drivers** (HTTP 8123 / native 9000). Install a ClickHouse extension from the Driver Manager or a local `.zip` / `.qext`. |

The **Demo Playground** (a bundled SQLite database) needs none of this.

## Headless modes

"Headless" means no display and no window. There are three levels, each one
command and each runnable in a container or on a CI runner
(tracked in [#1487](https://github.com/QueryaHub/Querya-Desktop/issues/1487)).

| Level | What | Command |
|-------|------|---------|
| L0 | unit, widget, e2e and guard tests | `flutter test --exclude-tags=golden` |
| L1 | an extension against a real database, no GUI | `querya-ext-tester ./ext --connect '{...}' --sandbox` (see *Testing an extension*) |
| L2 | the real app under a virtual display, in portable mode | `scripts/dev/headless_app.sh` |
| L2 + MCP | the same, with the MCP server on and a client reading a fixture through `querya-mcp` | `scripts/dev/headless_mcp_check.sh --mcp PATH` |

What each level needs from the database stack (start only that, by service name):

| Level | Containers |
|-------|------------|
| L0 | none; the live MySQL test needs `docker compose --profile live-tests up -d --wait mysql-live` |
| L1 | the database the extension talks to, e.g. `docker compose up -d --wait postgres` (or `clickhouse`, `redis`, `mongo`) |
| L2, L2 + MCP | none: the fixture is a throw-away SQLite file |

L1 needs a tester built from 0.4.19 or newer: older ones exited 0 whatever the
result.

### L2: `scripts/dev/headless_app.sh`

Starts Xvfb on a free display, runs a **copy** of a built bundle with
`QUERYA_PORTABLE=1` (so its `QueryaData` is a throw-away profile and the bundle
stays untouched), waits for the window, keeps watching for a few seconds, and
stops everything.

```bash
flutter build linux --release                  # or --debug
scripts/dev/headless_app.sh                    # picks build/linux/x64/release/bundle
scripts/dev/headless_app.sh --bundle path/to/bundle --screenshot out/shot.png --log out/app.log
```

Exit code 0: the app started, showed a window and stayed up; 1: it died or no
window appeared (the last lines of its output are printed); 2: a missing bundle
or tool. It needs `xvfb`, plus `xdotool` or `xwininfo` to see the window and
ImageMagick (`import`) for `--screenshot`; all of them are in the CI job below,
the dev container image has Xvfb.

The [Headless smoke (L2)](../.github/workflows/headless-smoke.yml) workflow builds
the Linux bundle and runs the script (on changes to it, weekly, and on demand),
keeping the screenshot and the log as an artifact.

Two more options let a script drive the running app:

- `--seed-sql FILE` applies SQL to the profile database (`querya.db`). The app
  starts once to create and migrate it, is stopped, `sqlite3` applies the file,
  and the app starts again. Use the same `app_settings` keys and tables the UI
  writes, so a test needs no code in the app.
- `--run COMMAND` runs a command once the window is up and keeps the app alive
  meanwhile; its exit code becomes the script's. The command gets
  `QUERYA_MCP_ENDPOINT` (this run's own endpoint file, so no other instance can
  answer), `QUERYA_HEADLESS_DB` and `QUERYA_HEADLESS_DATA`.

### L2 + MCP: `scripts/dev/headless_mcp_check.sh`

```bash
dart compile exe packages/querya_mcp_bridge/bin/querya_mcp.dart -o build/querya-mcp
scripts/dev/headless_mcp_check.sh --mcp build/querya-mcp --bundle build/linux/x64/release/bundle
```

It creates a fixture SQLite database with two connections, turns the MCP server
on and shares only one of them (the same settings keys the Preferences page
writes), starts the app under Xvfb and runs `scripts/dev/mcp_stdio_check.py`: a
small MCP client that talks to the real `querya-mcp` and checks `initialize`,
`tools/list`, that only the shared connection is listed, the table, its columns
and data, that a `DELETE` is refused and changes nothing, and that the unshared
connection is refused. It needs `sqlite3` and `python3` besides what L2 needs.
The same step runs in the Headless smoke workflow.

A window under Xvfb is all the MCP server needs, so there is no separate
"headless Querya" mode: `querya-mcp` still needs a running Desktop, and the
virtual display provides it.

## Run the app in the container

The container has no display of its own. Two ways:

- **Headless smoke:** start a virtual display and run the app, or just run the
  tests.

  ```bash
  Xvfb :99 -screen 0 1280x800x24 &   # DISPLAY=:99 is already set
  flutter run -d linux
  ```

- **See the window on a Linux host** (not part of the repository's
  configuration, add it to your own `devcontainer.json` if you want it):

  ```jsonc
  "mounts": ["source=/tmp/.X11-unix,target=/tmp/.X11-unix,type=bind"],
  "containerEnv": { "DISPLAY": "${localEnv:DISPLAY}" }
  ```

  plus `xhost +local:` on the host. Wayland-only hosts need XWayland.

For day-to-day UI work running Querya on the host is simpler; the container is
best for builds, tests and the database stack.

## Run the tests

CI is the source of truth; the same commands work in the container.

```bash
flutter pub get
flutter test --exclude-tags=golden                       # everything CI runs
scripts/ci/test_sections.sh list                         # core-data, core-extensions, ...
flutter test --exclude-tags=golden \
  $(scripts/ci/test_sections.sh paths features-workspace) # one section
flutter test test/e2e                                    # scenario tests
scripts/ci/test_sections.sh check                        # every test is in a section
```

- **No database server is needed** for the suite: widget and e2e tests start the
  app on an isolated data directory, an empty `LocalDb` and in-memory secrets
  ([`test/e2e/README.md`](../test/e2e/README.md)).
- **Goldens** are tagged `golden` and excluded in CI; run them only when you
  change the UI they cover.
- **Extension sandbox tests** need `bubblewrap` (installed in the image) and
  unprivileged user namespaces; without them they skip. Inside a container they
  may still skip because nested namespaces are restricted (run it with
  `--security-opt seccomp=unconfined` or add `"runArgs": ["--privileged"]` to
  your own `devcontainer.json` if you need them locally): CI runs them on a VM.
- **Analysis:** `flutter analyze`; CI runs it on every PR.

### The live MySQL test

`test/core/database/stream_take_drain_test.dart` talks to a real MySQL on
`127.0.0.1` and **skips** when there is none or when it cannot log in. It reads
`MYSQL_PORT` (default 3306), `MYSQL_USER`, `MYSQL_PASSWORD` and `MYSQL_DATABASE`
(defaults `querya`) and connects **without TLS**, so the stack's MySQL 8.4
(`caching_sha2_password`) does not work for it. The `live-tests` compose profile
starts the server CI uses, MySQL 8.0 with `mysql_native_password`, on its own
port:

```bash
cd docker
docker compose --profile live-tests up -d --wait mysql-live     # host port 3307, MYSQL_LIVE_PORT to change
cd ..
MYSQL_PORT=3307 flutter test test/core/database/stream_take_drain_test.dart
```

Inside the dev container the start script forwards `localhost:3307` to it when
the service is running (re-run the script after starting the profile).

### Testing an extension

Build and run the tester the way CI does it:

```bash
scripts/ci/build_ext_tester.sh build/ext-tester/querya-ext-tester
build/ext-tester/querya-ext-tester ./my-extension --target-version 0.5.0
```

See [extension-testing.md](extension-testing.md) for the options, reports and
the GitHub Action. The exit code is 0 on success, 1 when a check failed and 2 on
a usage error.

## For extension authors

You do not need this repository to write a database-driver extension. Start from
[QueryaHub/extension-template](https://github.com/QueryaHub/extension-template)
(a Rust driver with a dev container, a test database and CI). The pieces it uses:

- the **Dev Container Feature** `ghcr.io/queryahub/features/querya-ext-tester`
  installs `querya-ext-tester` from a release, checked against `SHA256SUMS.txt`
  (see [extension-testing.md](extension-testing.md#dev-container-feature));
- **test database images** `ghcr.io/queryahub/querya-testdb-{postgres,mysql,mongo,clickhouse,redis}:<version>`
  are the `docker/<db>` seeds baked into the official images, no bind mounts.
  Built from `docker/<db>/Dockerfile.testdb`; a new `Dockerfile.testdb` adds a
  database to the build by itself.

## Known gaps

- **The extension registry** (registry CI and `StaticRegistryRepository`) and the
  release hooks that publish the Feature and the images are not done yet; they
  are tracked in [#1487](https://github.com/QueryaHub/Querya-Desktop/issues/1487).
  Until then the images are published by hand with the *Test database images*
  workflow.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Docker is not reachable from the container` on start | Check that the host daemon runs and the `docker-outside-of-docker` feature is installed, then `bash scripts/dev/devcontainer_start.sh`. |
| `not healthy after 180s: ...` on start | A service is still starting or failed: `docker compose -f docker/docker-compose.yml ps` and `logs <service>`; raise `QUERYA_STACK_TIMEOUT` for a slow machine. |
| `port is already allocated` | A local PostgreSQL / MySQL / Redis uses the port. Set another one in `docker/.env` (`POSTGRES_PORT`, `MYSQL_PORT`, ...). |
| Connection refused to `localhost` from inside the container | The forwards are started by the start script: run `bash scripts/dev/devcontainer_start.sh` again (after a `docker compose down` / `up`), or use the service names (`postgres`, `mysql`, ...). |
| MySQL: connection refused or *requires a secure connection* | Tick **Use SSL/TLS** in the form (MySQL 8.4 uses `caching_sha2_password`). |
| MongoDB: authentication failed | The authentication database is `admin`, not `querya`. |
| Seeds missing or outdated | `docker compose down -v && docker compose up -d`. |
| MySQL / MongoDB / ClickHouse show `starting` for a while | They have a start period of 30–40 s; wait for `healthy`. |
| `flutter test` hangs or is slow in the container | Give Docker at least 4 CPUs and 8 GB, and run one section at a time. |
