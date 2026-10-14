# Dev container and local test databases

How to open Querya Desktop in the repository's dev container, start the local
database stack, connect Querya to it and run the tests. For the plain
(non-container) workflow see [CONTRIBUTING.md](../CONTRIBUTING.md); for the
list of seeded data see the header of [`docker/docker-compose.yml`](../docker/docker-compose.yml).

## What is in the box

| File | What it does |
|------|--------------|
| [`.devcontainer/devcontainer.json`](../.devcontainer/devcontainer.json) | The dev container definition: build, features, post-create / post-start commands, forwarded ports, VS Code extensions, host requirements (4 CPUs, 8 GB). |
| [`.devcontainer/Dockerfile`](../.devcontainer/Dockerfile) | `ghcr.io/cirruslabs/flutter` plus the Linux desktop toolchain (clang, cmake, ninja, GTK 3, libsecret, SQLite headers, Xvfb) and the Docker CLI with the Compose plugin. `DISPLAY` is `:99`. |
| [`docker/docker-compose.yml`](../docker/docker-compose.yml) | The database stack (project `querya-dev`): PostgreSQL 16, MySQL 8.4, Redis 7, MongoDB 7, ClickHouse 24.8 and a seeded SQLite file. |

When the container is created it runs `flutter config --enable-linux-desktop`
and `flutter pub get`; every time it starts it tries
`docker compose -f docker/docker-compose.yml up -d` and prints a hint if Docker
is not reachable.

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

`localhost` inside the container is the container itself, **not** the host, so
`localhost:5432` finds nothing even though the port is "forwarded" (the forward
goes from the container to your machine, and the databases do not listen in the
container). Pick one:

1. **Join the stack's network** (works on Linux Docker Engine and Docker Desktop):

   ```bash
   docker network connect querya-dev_default "$(hostname)"
   ```

   Then use the service names as hosts: `postgres`, `mysql`, `redis`, `mongo`,
   `clickhouse` (with the container-side ports 5432, 3306, 6379, 27017, 8123).
2. **Docker Desktop only:** `host.docker.internal` with the host ports.
3. **Share the network namespace** of a database with the dev container, so
   that `127.0.0.1` works for tests that hard-code it (see the live MySQL test
   below): start that one container with `--network container:$(hostname)`.

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

"Headless" means no display and no window. There are three levels; the first
two work today, the third is a recipe that is not wrapped in a script yet
(tracked in [#1487](https://github.com/QueryaHub/Querya-Desktop/issues/1487)).

| Level | What | Command |
|-------|------|---------|
| L0 | unit, widget, e2e and guard tests | `flutter test --exclude-tags=golden` |
| L1 | an extension against a real database, no GUI | `querya-ext-tester ./ext --connect '{...}' --sandbox` (see *Testing an extension*) |
| L2 | the real app under a virtual display, in portable mode | see below |

L1 needs a tester built from 0.4.19 or newer: older ones exited 0 whatever the
result.

L2, by hand (untested in the container, it is the same recipe as a normal
Linux run):

```bash
Xvfb :99 -screen 0 1280x800x24 &            # DISPLAY=:99 is already set
QUERYA_PORTABLE=1 flutter run -d linux       # data goes to ./QueryaData of the bundle
import -window root shot.png                # ImageMagick, if installed
```

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
- **Extension sandbox tests** need `bubblewrap` (`sudo apt-get install bubblewrap`)
  and unprivileged user namespaces; without them they skip. Inside a container
  they may also skip because nested namespaces are restricted: CI runs them on a
  VM.
- **Analysis:** `flutter analyze`; CI runs it on every PR.

### The live MySQL test

`test/core/database/stream_take_drain_test.dart` talks to a real MySQL on
`127.0.0.1` and **skips** when there is none or when it cannot log in. It reads
`MYSQL_PORT` (default 3306), `MYSQL_USER`, `MYSQL_PASSWORD` and `MYSQL_DATABASE`
(defaults `querya`) and connects **without TLS**, so the stack's MySQL 8.4 does
not work for it. Use a server like the one CI starts:

```bash
docker run -d --name mysql-live -p 3307:3306 \
  -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=querya \
  -e MYSQL_USER=querya -e MYSQL_PASSWORD=querya \
  mysql:8.0 --default-authentication-plugin=mysql_native_password

MYSQL_PORT=3307 flutter test test/core/database/stream_take_drain_test.dart
```

Inside the dev container add `--network container:$(hostname)` (and drop
`-p`) so that `127.0.0.1:3306` is that server, and leave `MYSQL_PORT` unset.

### Testing an extension

Build and run the tester the way CI does it:

```bash
scripts/ci/build_ext_tester.sh build/ext-tester/querya-ext-tester
build/ext-tester/querya-ext-tester ./my-extension --target-version 0.5.0
```

See [extension-testing.md](extension-testing.md) for the options, reports and
the GitHub Action. The exit code is 0 on success, 1 when a check failed and 2 on
a usage error.

## Known gaps

- **Flutter version.** CI pins Flutter **3.47.1**; the dev container image is
  `ghcr.io/cirruslabs/flutter:3.41.6` and the image registry has no 3.47.x tag
  yet. To match CI inside the container:

  ```bash
  FLUTTER_ROOT="$(dirname "$(dirname "$(readlink -f "$(which flutter)")")")"
  git -C "$FLUTTER_ROOT" fetch --tags
  git -C "$FLUTTER_ROOT" checkout 3.47.1
  flutter precache --linux && flutter pub get
  ```

  This changes the image's SDK for that container only.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Docker stack not started` on start | Docker is not reachable from the container: check that the host daemon runs and the `docker-outside-of-docker` feature is installed, then `cd docker && docker compose up -d`. |
| `port is already allocated` | A local PostgreSQL / MySQL / Redis uses the port. Set another one in `docker/.env` (`POSTGRES_PORT`, `MYSQL_PORT`, ...). |
| Connection refused to `localhost` from inside the container | See *From inside the dev container* above: use the service names after `docker network connect`. |
| MySQL: connection refused or *requires a secure connection* | Tick **Use SSL/TLS** in the form (MySQL 8.4 uses `caching_sha2_password`). |
| MongoDB: authentication failed | The authentication database is `admin`, not `querya`. |
| Seeds missing or outdated | `docker compose down -v && docker compose up -d`. |
| MySQL / MongoDB / ClickHouse show `starting` for a while | They have a start period of 30–40 s; wait for `healthy`. |
| `flutter test` hangs or is slow in the container | Give Docker at least 4 CPUs and 8 GB, and run one section at a time. |
