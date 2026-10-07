# Testing extensions in CI

`querya-ext-tester` is a headless runner for Querya database-driver
extensions. It starts your extension the way Querya Desktop does, drives its
JSON-RPC lifecycle and reports what a user would run into — without a display
server, Flutter or the Querya Desktop source tree.

## What it checks

1. **`manifest.json`** — `id`, `name`, `version`, `type: "database_driver"`,
   `main`, `engines.querya_desktop` (against the emulated host version),
   `contributions.drivers[]` (`driverId`, `displayName`). Every problem is
   reported with its JSON path.
2. **Launch** — the `main` entry point exists and starts.
3. **RPC lifecycle**, in this order: `system.handshake`, `system.ping`,
   `db.connect`, `db.getCapabilities`, `db.getServerStats`,
   `db.getSchemaTree`, `db.query` (must return `{"columns": [...], "rows":
   [...]}`), `db.getTableSchema` (only with `--table`), `db.disconnect`,
   `system.shutdown` (the process must exit afterwards).

`system.handshake`, `system.shutdown` and the `db.connect` / `db.disconnect` /
`db.query` / `db.getSchemaTree` calls are **required**: a failure fails the
run. `system.ping`, `db.getCapabilities`, `db.getServerStats` and
`db.getTableSchema` are **recommended**: the host falls back gracefully, so
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
| `--timeout-ms <n>` | per-request timeout (default 5000) |
| `--junit <path>` / `--tap <path>` | write a JUnit XML / TAP report |
| `--no-color` | plain output |

Exit codes: `0` all checks passed (warnings and skips do not fail), `1` a
check failed, `2` bad command line.

Credentials only travel inside the `db.connect` payload over the plugin's
stdio; they are never put on the command line of the plugin or into its
environment. Use a throwaway database in CI.

## GitHub Actions

This repository contains a composite action in
`.github/actions/test-extension`. Until it is published as
`QueryaHub/action-test-extension`, reference it by path:

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
      - uses: QueryaHub/Querya-Desktop/.github/actions/test-extension@0.4.18
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

## Running from source

Inside a Querya Desktop checkout (needs the Flutter SDK for `pub get`):

```bash
flutter pub get
dart run bin/querya_ext_tester.dart ./my-extension --target-version 0.5.0
```
