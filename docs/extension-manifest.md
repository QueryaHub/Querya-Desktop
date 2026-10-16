# The extension manifest (`manifest.json`)

Every extension is a folder or zip with a `manifest.json` at its root. This is
the reference for that file: what the fields mean, what the tester and the app
check, and how the format itself is versioned.

Start from a working one: the [extension template](https://github.com/QueryaHub/extension-template)
has a complete manifest of a database driver. How an extension gets from there
to the Marketplace is in [extension-registry.md](extension-registry.md); how to
test it is in [extension-testing.md](extension-testing.md).

## A database driver

```json
{
  "manifestVersion": 1,
  "id": "acme.redis-driver",
  "name": "Redis driver",
  "version": "1.0.0",
  "publisher": "Acme",
  "type": "database_driver",
  "main": "bin/redis-driver",
  "engines": { "querya_desktop": ">=0.4.19" },
  "capabilities": { "databaseDriver": true },
  "sandbox": {
    "engine": "process",
    "permissions": {
      "network": { "mode": "connection_host_only", "allow_ssl": false },
      "filesystem": { "scratch_mb": 10, "access": "scratch_only" },
      "resources": { "memory_mb": 128, "max_open_files": 32, "timeout_seconds": 60 }
    }
  },
  "contributions": {
    "drivers": [
      {
        "driverId": "acme-redis",
        "displayName": "Redis (Acme)",
        "defaultPort": 6379,
        "connectionFormSchema": "assets/connection_form.json"
      }
    ]
  }
}
```

## Fields

| Field | Required | Meaning |
|-------|----------|---------|
| `manifestVersion` | no | The format of this file: a whole number, **1 when absent**. See [Versioning](#versioning-of-the-manifest-format) |
| `id` | yes | `publisher.name` in lowercase, digits and dashes. The install folder, the registry record (`extensions/<id>.json`) and everything else key on it |
| `name` | yes | Shown in the Marketplace and the Extensions list |
| `version` | yes | The extension's own version, `x.y.z`. The registry requires it to equal the record's |
| `publisher` | no | Shown as the author (`author` is read when `publisher` is missing) |
| `type` | yes | `database_driver`, `theme` or `script`. Only `database_driver` can use the OS process sandbox, and only it is run by the tester |
| `main` | drivers | The executable, relative to the root. Must be a file in the archive |
| `engines.querya_desktop` | yes | The Querya Desktop versions it runs on: `>=x.y.z` or `^x.y.z`. The app hides the extension outside the range; the tester warns when the emulated host is outside it |
| `description`, `icon`, `homepage`, `license`, `tags`, `preview` | no | Marketplace listing. `icon` is a path inside the archive |
| `capabilities` | no | `databaseDriver`, `sduiForms` flags |
| `sandbox` | drivers | What the driver is allowed to do; see below |
| `contributions` | drivers | `drivers[]` (`driverId`, `displayName`, `defaultPort`, `connectionFormSchema`, `icon`) and `commands[]` (`id`, `title`, `category`, `aliases`; commands need Querya Desktop 0.4.16 or newer). `contributes` is accepted as an alias |

Fields the marketplace adds (`downloadUrl`, `sha256`) are not written by the
author: the registry builds them from the release asset.

## The sandbox block

A database driver runs as its own process inside an OS sandbox (`bubblewrap` on
Linux, `sandbox-exec` on macOS). It declares what it needs, and the app refuses
anything beyond the policy:

| Setting | Allowed | Notes |
|---------|---------|-------|
| `engine` | `process` | `wasm` and `quickjs` are reserved for embedded scripts |
| `permissions.network.mode` | `connection_host_only` or `none` | Sockets only to the host the user configured. `allow_ssl` says it uses TLS |
| `permissions.filesystem` | `access: "scratch_only"`, `scratch_mb` up to 100 | The only writable place is a scratch directory |
| `permissions.resources` | `memory_mb` up to 512, `max_open_files` up to 64 | `timeout_seconds` is optional |

A driver without a sandbox block, or with one the policy rejects, is shown in the
Marketplace as a **Preview** listing and cannot be installed.

## What checks the manifest

| Where | What it checks |
|-------|----------------|
| `querya-ext-tester` (the `manifest` step) | Required fields, `type`, `main`, `engines` against `--target-version`, `manifestVersion` against that host, `contributions.drivers[]`. Every problem comes with its JSON path |
| The registry's CI (`registry.py check`) | `manifest.json` at the archive root, `id` and `version` equal the record's, `engines.querya_desktop` present, a driver's `main` is in the archive, `manifestVersion` is a format Querya defines. All platform archives of a record agree on `id`, `version`, `name`, `type`, `engines` and `manifestVersion` |
| The app, when it lists, installs or loads | The sandbox policy, the preview rule, `manifestVersion` not newer than it reads, the driver package (`main` exists) |

## Versioning of the manifest format

Three different versions meet in the file:

| Field | Versions | Who raises it |
|-------|----------|---------------|
| `version` | the extension | the author, for each release |
| `engines.querya_desktop` | the hosts the author tested | the author |
| `manifestVersion` | **the format of `manifest.json`** | Querya, when the format changes |

`manifestVersion` is **1 when it is absent**, so every manifest written so far is
format 1 and nothing has to be changed. Writing `"manifestVersion": 1` is
optional but makes the format explicit (the template does).

An older Querya Desktop must not guess what a newer manifest means, so one in a
format it does not read is refused outright: the tester reports an error for the
host it emulates, the Marketplace does not list it, and the installer and the
local loader say to update Querya Desktop. A format that a host reads is read
completely.

### When the format changes

Keep a change **additive** when it can be: a new optional field that an older
host ignores safely needs no new `manifestVersion`, only a line in this document
and, if the tester should warn about it, a rule in the validator for the hosts
that know it. Raise the format only for a change an older host would misread: a
field that changes the meaning of an existing one, a removed or renamed field, a
stricter requirement.

To add format *N*:

1. `ExtensionManifest.currentManifestVersion` → *N* (`lib/core/extensions/models/extension_manifest.dart`).
2. `ExtensionProtocolProfile._manifestFormats`: add `(N, <first Querya Desktop release that reads it>)`.
3. Teach the reading code (`ExtensionManifest.fromJson` and what uses it) the new shape, keeping format 1 working.
4. Add the rule to `validateExtensionManifest`, gated on `profile.manifestVersion >= N` where it only applies to the new format.
5. `QueryaHub/extensions`: `MAX_MANIFEST_VERSION` in `scripts/registry.py` → *N*, with tests.
6. Update this document, the [extension template](https://github.com/QueryaHub/extension-template) if its manifest should use the new format, and the CHANGELOG.
7. Tests: the validator on a host before and after the release, the support check, the local registry skip, the registry reader.

Authors then opt in with `"manifestVersion": N` once the hosts they support
(`engines`) all read it.
