# Testing extensions in CI

`querya-ext-tester` is a headless runner for Querya database-driver
extensions. It starts your extension the way Querya Desktop does, drives its
JSON-RPC lifecycle and reports what a user would run into — without a display
server, Flutter or the Querya Desktop source tree.

## What it checks

1. **`manifest.json`** — `id`, `name`, `version`, `type: "database_driver"`,
   `main`, `engines.querya_desktop` and `manifestVersion` (both against the
   emulated host version; see [extension-registry.md](extension-registry.md#versions-what-is-checked-against-what)),
   `contributions.drivers[]` (`driverId`, `displayName`). Every problem is
   reported with its JSON path.
2. **Launch** — the `main` entry point exists and starts.
3. **RPC lifecycle**, in this order: `system.handshake`, `system.ping`,
   `system.injectCredentials` (only when `--connect` has a `password`),
   `db.connect`, `db.getCapabilities`, `db.getServerStats`,
   `db.getSchemaTree`, `db.query` (must return `{"columns": [...], "rows":
   [...]}`), `db.getTableSchema` (only with `--table`), `db.disconnect`,
   `system.shutdown` (the process must exit afterwards).

`system.handshake`, `system.shutdown` and the `db.connect` / `db.disconnect` /
`db.query` / `db.getSchemaTree` calls are **required**: a failure fails the
run. `system.ping`, `system.injectCredentials`, `db.getCapabilities`,
`db.getServerStats` and `db.getTableSchema` are **recommended**: the host falls back gracefully, so
the runner only warns. Methods the emulated host version does not send are
skipped.

## Host versions

`--target-version x.y.z` selects the protocol the emulated host speaks:

| Host version | Adds |
| --- | --- |
| 0.4.11 | extension RPC: handshake, connect/disconnect, query, schema tree, capabilities, server stats, ping, shutdown |
| 0.4.14 | `db.getTableSchema` |
| 0.4.16 | `commands.execute` (Command Palette actions) |

Versions before 0.4.11 are rejected: extensions did not exist yet. Test
against several versions with a CI matrix (below).

## Download

Every GitHub Release of Querya Desktop attaches the tester for each platform:

- `querya-ext-tester-v{version}-linux-x64.tar.gz`
- `querya-ext-tester-v{version}-macos-arm64.tar.gz`
- `querya-ext-tester-v{version}-macos-x64.tar.gz`
- `querya-ext-tester-v{version}-windows-x64.zip`

They are standalone ahead-of-time executables with no runtime dependencies.
Verify the download against `SHA256SUMS.txt` from the same release.

## Usage

```bash
querya-ext-tester ./my-extension \
  --target-version 0.4.18 \
  --connect '{"host":"localhost","port":9000,"username":"default"}' \
  --query 'SELECT 1' \
  --table users \
  --junit report.xml
```

| Option | Meaning |
| --- | --- |
| `--target-version <x.y.z>` | host version to emulate (default `0.5.0`) |
| `--connect <json\|file>` | extra `db.connect` parameters, inline or from a file |
| `--query <sql>` | statement for the `db.query` check (default `SELECT 1`) |
| `--table <name>` | also check `db.getTableSchema` |
| `--database <name>` | database passed to `db.connect` |
| `--sandbox` | run the plugin in the OS sandbox (`bwrap` on Linux, `sandbox-exec` on macOS) when available |
| `--manifest-only` | check `manifest.json` against `--target-version` and stop: the extension is not started, so no database and no executable are needed. For a quick lint, or a CI step with no database. Not in 0.4.19 or earlier |
| `--strict` | warnings fail the run too (exit `1`): a recommended method that errors, or a sandbox that could not be applied. Not in 0.4.19 or earlier |
| `--timeout-ms <n>` | per-request timeout (default 5000) |
| `--junit <path>` / `--tap <path>` | write a JUnit XML / TAP report |
| `--trace <path>` | write every RPC round trip as JSON: method, time, request and response size and a bounded view of the data (see *Following the data*) |
| `--no-color` | plain output |

Exit codes: `0` all checks passed (warnings and skips do not fail, unless
`--strict`), `1` a check failed, `2` bad command line.

A `password` in `--connect` is sent the way the app sends it: with
`system.injectCredentials` before `db.connect`, and left out of the `db.connect`
payload. A driver that reads its password only from the injected secret (as the
ClickHouse driver does) therefore works with the tester. Credentials travel over
the plugin's stdio only; they are never put on the command line of the plugin or
into its environment. Use a throwaway database in CI.

## Following the data: `--trace`

A green run says the lifecycle works. `--trace trace.json` shows *what* went
over the wire, so you can see whether the data of your driver arrives as the
host expects:

```json
{
  "extension": "acme.clickhouse-driver",
  "targetVersion": "0.5.0",
  "success": true,
  "totalMs": 41,
  "checks": [{ "name": "db.query", "status": "passed", "ms": 3 }],
  "rpc": [
    { "method": "db.connect", "ms": 12, "ok": true, "requestBytes": 76,
      "responseBytes": 28, "request": { "host": "db", "password": "***" } },
    { "method": "db.query", "ms": 3, "ok": true, "requestBytes": 47,
      "responseBytes": 1760,
      "response": { "columns": ["id", "name"], "rows": [[0, "user0"], "… (+7 more)"] } }
  ]
}
```

- Values of keys that look like secrets (`password`, `secret`, `token`,
  `passphrase`, ...) are written as `***`.
- Responses are cut: at most 5 items per list, strings of at most 120
  characters. The file shows the shape and a sample, not a copy of your data;
  still, use a throwaway database and do not publish traces of real data.
- A failing call is recorded with its `error`, so a CI artifact is enough to
  see which call broke and after how long.

## Docker image

`ghcr.io/queryahub/querya-headless:<version>` (and `:latest`) is the tester of
that Querya Desktop release in a pinned environment: Debian (glibc), the
tester checked against the release's `SHA256SUMS.txt`, `bubblewrap` for
`--sandbox`, a non-root user, entry point `querya-ext-tester`. Nothing else is
needed on the machine: no Flutter, no display, no Querya install.

```bash
docker pull ghcr.io/queryahub/querya-headless:latest

docker run --rm \
  -v "$PWD/dist:/ext:ro" -v "$PWD/out:/out" \
  ghcr.io/queryahub/querya-headless:0.4.19 /ext \
  --connect '{"host":"db","port":5432}' \
  --junit /out/junit.xml --trace /out/trace.json
```

The extension's `main` is a native executable and runs **inside** the image, so
build it for Linux x86-64 against glibc. To reach a database from the image,
put both on one Docker network and use the database's service name as the host.

### In CI, next to a test database

```yaml
jobs:
  rpc:
    runs-on: ubuntu-latest
    services:
      db:
        image: postgres:16-alpine
        env: { POSTGRES_PASSWORD: querya, POSTGRES_USER: querya, POSTGRES_DB: querya }
        options: >-
          --health-cmd "pg_isready -U querya" --health-interval 5s
          --health-retries 12
    steps:
      - uses: actions/checkout@v4
      - run: ./build.sh                        # writes ./dist with manifest.json
      - name: RPC and data check
        run: |
          mkdir -p out && chmod 777 out
          docker run --rm --network "${{ job.services.db.network }}" \
            -v "$PWD/dist:/ext:ro" -v "$PWD/out:/out" \
            ghcr.io/queryahub/querya-headless:0.4.19 /ext \
            --target-version 0.5.0 \
            --connect '{"host":"db","port":5432,"username":"querya","password":"querya","database":"querya"}' \
            --query 'SELECT 1' --junit /out/junit.xml --trace /out/trace.json
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: rpc-trace, path: out/ }
```

Use the same `docker run` locally with `--network querya-dev_default` against
the stack from [dev-containers.md](dev-containers.md) (`host` is the service
name, for example `postgres`).

### `--sandbox` in a container

The OS sandbox is `bubblewrap`, which needs unprivileged user namespaces. Many
container runtimes block them by default; the tester then runs the plugin
without the sandbox and says so in the report. To test the sandboxed run, start
the container with `--security-opt seccomp=unconfined` (and, on hosts that
restrict namespaces with AppArmor, `--security-opt apparmor=unconfined`), or
run the tester directly on the CI runner with the action below.

The fields of `manifest.json` are in [extension-manifest.md](extension-manifest.md).

Starting a new extension? The [extension template](https://github.com/QueryaHub/extension-template)
has all of this wired up, and [extension-registry.md](extension-registry.md)
shows how a tested extension gets into the Marketplace.

## Dev Container Feature

In a dev container the tester can be installed as a Feature. It downloads the
release archive, checks it against `SHA256SUMS.txt` and puts `querya-ext-tester`
in `PATH` (Linux x86_64, Debian-family images):

```json
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/queryahub/features/querya-ext-tester:1": { "version": "latest" }
  }
}
```

`version` is a Querya Desktop release (`0.4.19`) or `latest`. Releases before
0.4.19 are refused: their exit codes were not reliable. The source is in
`devcontainer-features/src/querya-ext-tester`.

## GitHub Actions

This repository contains a composite action in
`.github/actions/test-extension`. Until it is published as
`QueryaHub/action-test-extension`, reference it by path (pin a release tag once one
ships the action; `dev` is shown here):

```yaml
jobs:
  test-extension:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        querya-version: ['0.4.18', '0.5.0']
    steps:
      - uses: actions/checkout@v4
      - name: Build the driver
        run: ./build.sh
      - uses: QueryaHub/Querya-Desktop/.github/actions/test-extension@dev
        with:
          querya-version: ${{ matrix.querya-version }}
          extension-dir: ./dist/my-extension
          connect: '{"host":"localhost","port":9000}'
          junit-path: junit.xml
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: junit-${{ matrix.querya-version }}
          path: junit.xml
```

The action downloads the matching tester, checks its SHA-256 against the
release's `SHA256SUMS.txt` and runs it. Inputs: `querya-version`
(default `latest`), `target-version`, `extension-dir`, `connect`, `query`,
`table`, `sandbox`, `junit-path`, `tap-path`.

## Other CI systems

Download and extract the archive in any shell step, then run the binary:

```bash
curl -fsSLO "https://github.com/QueryaHub/Querya-Desktop/releases/download/0.4.18/querya-ext-tester-v0.4.18-linux-x64.tar.gz"
tar -xzf querya-ext-tester-v0.4.18-linux-x64.tar.gz
./querya-ext-tester ./my-extension --target-version 0.4.18 --junit junit.xml
```

GitLab CI, Jenkins and Bitbucket read the JUnit XML file as a test report.

## Recipes by language

The tester only needs a directory with `manifest.json` and the built entry
point named by `main`. Build first, then point it at the output directory.
Use a throwaway database service in CI and pass credentials through `--connect`.

### Go

```yaml
jobs:
  test-extension:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        querya-version: ['0.4.18', '0.5.0']
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: stable }
      - name: Build
        run: |
          mkdir -p dist
          CGO_ENABLED=0 go build -o dist/driver ./cmd/driver
          cp manifest.json dist/
      - uses: QueryaHub/Querya-Desktop/.github/actions/test-extension@dev
        with:
          querya-version: ${{ matrix.querya-version }}
          extension-dir: dist
          connect: '{"host":"localhost","port":5432}'
```

### Rust

```yaml
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - name: Build
        run: |
          cargo build --release
          mkdir -p dist
          cp target/release/my-driver dist/driver
          cp manifest.json dist/
      - uses: QueryaHub/Querya-Desktop/.github/actions/test-extension@dev
        with:
          extension-dir: dist
```

### TypeScript / Node

```yaml
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - name: Build
        run: |
          npm ci
          npm run build            # emits dist/index.js
          cp manifest.json dist/   # manifest "main" must point at the entry that is run
      - uses: QueryaHub/Querya-Desktop/.github/actions/test-extension@dev
        with:
          extension-dir: dist
```

For interpreted entry points make sure the file is executable (or has a
shebang) in the same way Querya Desktop would launch it.

### GitLab CI

There is no dedicated Docker image; download the release binary in any image
that has `curl`:

```yaml
test-extension:
  image: debian:stable-slim
  parallel:
    matrix:
      - QUERYA_VERSION: ['0.4.18', '0.5.0']
  before_script:
    - apt-get update && apt-get install -y curl ca-certificates tar
    - curl -fsSLO "https://github.com/QueryaHub/Querya-Desktop/releases/download/${QUERYA_VERSION}/querya-ext-tester-v${QUERYA_VERSION}-linux-x64.tar.gz"
    - tar -xzf "querya-ext-tester-v${QUERYA_VERSION}-linux-x64.tar.gz"
  script:
    - ./querya-ext-tester ./dist --target-version "$QUERYA_VERSION" --junit junit.xml --no-color
  artifacts:
    when: always
    reports:
      junit: junit.xml
```

## Debugging locally

1. Run the tester against your build output with the same flags as CI. Failed
   checks print the JSON path of a manifest problem or the RPC method and error.
2. Raise the timeout while attaching a debugger: `--timeout-ms 60000`.
3. Test a single older host with `--target-version`; methods the emulated host
   does not send are reported as skipped.
4. Reproduce what a user sees in Querya Desktop with `--sandbox`, which starts
   the plugin in the same OS sandbox.
5. Capture machine-readable results with `--junit report.xml` or `--tap report.tap`.

Recommended methods only warn, and exit code `1` means a required check failed.
Add `--strict` (with `--sandbox` in CI) so a warning, in particular "OS sandbox
is not available", fails the run instead of passing as green.

## Running from source

Inside a Querya Desktop checkout (needs the Flutter SDK for `pub get`):

```bash
flutter pub get
dart run bin/querya_ext_tester.dart ./my-extension --target-version 0.5.0
```
