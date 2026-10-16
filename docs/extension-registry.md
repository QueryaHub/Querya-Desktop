# Extension registry

How a database-driver extension gets from an author's machine into Querya
Desktop's Marketplace, and what keeps it safe. There is no Marketplace server:
the catalog is a Git repository and one static file.

```
author ──► extension-template ──► release zip on GitHub ──► record PR to QueryaHub/extensions
                                                                      │  CI: download, SHA-256, archive,
                                                                      │  manifest, querya-ext-tester --sandbox
                                                                      ▼
Querya Desktop ◄── index.json (GitHub Pages) ◄── publish (on merge, nightly, on a Querya release)
```

| Piece | Where | What it does |
|-------|-------|--------------|
| `extension-template` | [QueryaHub/extension-template](https://github.com/QueryaHub/extension-template) | A working Rust driver with a dev container, a test database and CI. Click *Use this template*. |
| `querya-ext-tester` | Querya Desktop releases, the Dev Container Feature, the `test-extension` action | Runs the extension like the app does and checks its JSON-RPC lifecycle ([extension-testing.md](extension-testing.md)). |
| `querya-testdb-*` | `ghcr.io/queryahub/querya-testdb-{postgres,mysql,mongo,clickhouse,redis}:<version>` | The test databases, seeds inside. Built from `docker/<db>/Dockerfile.testdb`. |
| Registry | [QueryaHub/extensions](https://github.com/QueryaHub/extensions) | Records, CI, and `index.json` / `compat.json` on GitHub Pages. |
| `StaticRegistryRepository` | `lib/core/market/static_registry_repository.dart` | The app's reader of `index.json`. |

## Publishing an extension

1. Start from the template, or any project that produces a **zip** with
   `manifest.json` at its root (and, for a driver, the executable `main` points at).
2. Test it: `scripts/test.sh` in the template's dev container, or
   `querya-ext-tester ./dist --connect '{...}' --sandbox` against a
   `querya-testdb-*` container.
3. Publish a GitHub release with the zip as an asset.
4. Add `extensions/<id>.json` to the registry in a pull request (the format and
   what CI checks are in the registry's README). Everything the Marketplace
   shows is read from `manifest.json` **inside the archive**; the record only
   holds `id`, `version`, `downloadUrl`, `sha256` and an optional `testEnv`.
5. A new version is a change to `version`, `downloadUrl` and `sha256` in the same
   file. `"yanked": true` hides an extension without deleting its record.

The extension's binary runs in the registry's CI, inside the OS sandbox, in a job
with no secrets and a read-only token. Only a Linux x86-64 build is exercised.

## What the app trusts

`StaticRegistryRepository` reads `https://queryahub.github.io/extensions/index.json`:

```json
{
  "schema": 1,
  "generatedAt": "2026-10-16T18:59:53Z",
  "extensions": [
    {
      "id": "acme.redis-driver", "name": "Redis", "version": "1.0.0", "type": "database_driver",
      "engines": { "querya_desktop": ">=0.4.19" }, "main": "bin/driver",
      "downloadUrl": "https://github.com/acme/redis-driver/releases/download/v1.0.0/redis-driver.zip",
      "sha256": "…", "size": 232353
    }
  ]
}
```

- An index with another `schema` is refused, not half read.
- Hidden from the list: `yanked` entries, entries without a checksum, a
  `downloadUrl` that is not `https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>`,
  and extensions whose `engines.querya_desktop` range excludes the running
  version. One malformed entry does not hide the others.
- The index is cached for ten minutes; if a refresh fails the last good copy is
  served.
- Installing is the same pipeline as any marketplace install: the archive's
  SHA-256 must equal the index's, the archive is unpacked with path-traversal and
  zip-bomb limits, and the sandbox policy must accept the manifest.

The app picks it at startup (`lib/core/market/marketplace_selection.dart`), with
the running version as `hostVersion`, so the Extensions → Marketplace tab lists
what the registry publishes. While the registry is empty the tab says so; when
the registry cannot be reached it shows the reason and a *Retry* button.

Two build-time switches, for people working on the app or on a registry:

| `--dart-define` | Effect |
|-----------------|--------|
| `QUERYA_MARKETPLACE_INDEX=<url>` | read another `index.json` (a fork, a test registry); `http://localhost` is accepted in debug builds |
| `QUERYA_MARKETPLACE_MOCK=true` | the built-in demo catalog, for working on the Marketplace page; for debug and profile builds only |

`compat.json` lists, per extension and per Querya version in the registry's
`hosts.json`, `pass`, `fail` or `untested`. The app does not read it yet.

## Following Querya's releases

The [Release hooks](../.github/workflows/release-hooks.yml) workflow runs after a
**Release** succeeds and sends `repository_dispatch` `querya-release` with the
version to:

- **the registry**, which tests every record against that version too and adds a
  column to `compat.json` (raise `hosts.json` in a pull request to keep the
  column);
- **the template**, which pushes a branch `querya-<version>` that moves its test
  image tag and CI matrix, starts its Test workflow on it, and opens a pull
  request (or an issue pointing at the branch when the organization does not
  allow Actions to open pull requests).

The `querya-testdb-*` images and `querya-headless` have their own workflows on
the same Release. The Dev Container Feature does not follow releases: it
downloads the newest tester when it is installed.

### One-time setup

A dispatch into another repository needs a token that can write there. Create a
fine-grained personal access token (or a GitHub App token) with **Contents:
Read and write** on `QueryaHub/extensions` and `QueryaHub/extension-template`
and store it as the secret **`QUERYA_DISPATCH_TOKEN`** in this repository.
Without it the Release hooks only log a warning, and nothing breaks.

To let the template open its pull request itself, enable *Settings → Actions →
General → Allow GitHub Actions to create and approve pull requests* for the
organization. Without that the template opens an issue instead.

## The nightly check

The registry rebuilds the index every night from the records. A record whose
asset disappeared, changed its hash, or whose extension fails its tests on every
Querya version is **left out of the index** and gets an issue
`Registry check failed: <id>` (label `registry-check`) with the reason; the
issue closes itself when the record passes again. The rest of the index is still
published.
