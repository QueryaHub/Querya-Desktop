# Security model (local data)

Querya Desktop keeps **non-secret** connection metadata (host, port, user name, labels, folder ids) in a local SQLite file under the application support directory (see `LocalDb` in `lib/core/storage/local_db.dart`).

## Secrets (passwords and connection strings)

As of the current design:

- **Passwords** and **MongoDB-style connection strings** are **not** stored as plaintext in SQLite.
- They are written to the **platform secure store** via `flutter_secure_storage` (Keychain on macOS, Credential Manager / DPAPI on Windows, libsecret on typical Linux desktops).
- Keys are scoped per saved connection id (`ConnectionSecretsStore` in `lib/core/storage/connection_secrets_store.dart`).

On upgrade from older databases, existing plaintext secrets in SQLite are **migrated** into the secure store and the SQLite columns are cleared (schema version 5).

## Threat model (practical)

- Anyone with **full access to your user session** can usually read app data and may extract secrets depending on OS protections.
- The app does **not** implement network zero-trust controls. Local audit trails exist for executed data changes and for MCP calls.
- **SSH tunnels / jump hosts** are built in (see below); the tunnel does not protect against an attacker who already controls your user session.

## SSH tunnels (bastion hosts)

- **Loopback only:** the forwarded port is bound to `127.0.0.1` on an ephemeral port, never to a public interface.
- **Secrets:** SSH password, private key, passphrase and jump-host password are stored in the platform secure store next to the database password, not in SQLite. The tunnel configuration kept in the connection row (host, port, user, auth type, key *path*, fingerprint) is non-secret.
- **Credential hygiene:** secrets are read on demand when connecting, not when the sidebar loads, and database drivers clear their in-memory credentials once the handshake completes.
- **Host key verification:** with no pinned fingerprint the first key is accepted (trust on first use). Pin the server's SHA-256 fingerprint in the connection to reject a changed key; a mismatch fails the connection and reports the observed fingerprint.
- **Team sharing:** *Export Team Profile* writes connections without passwords or SSH secrets; importing re-scrubs the file.

## MCP server

Querya can serve the connections you share to AI clients over MCP ([mcp-server.md](mcp-server.md)). SQL written by a model is untrusted, so access is limited in three independent layers:

1. **Guard** (`McpSqlGuard`): one statement per call, only `SELECT` / `WITH` without data-modifying parts / `EXPLAIN` without `ANALYZE` / `SHOW` / `DESCRIBE` / `VALUES` and SQLite schema pragmas. Refused even inside a read: `SELECT ... INTO`, `INTO OUTFILE`, row locks, server functions with side effects (`pg_terminate_backend`, `pg_read_file`, `dblink`, `set_config`, `LOAD_FILE`, `load_extension`, ...) and MySQL executable comments (`/*! ... */`).
2. **Read-only database session:** PostgreSQL `default_transaction_read_only`, MySQL `SET SESSION TRANSACTION READ ONLY`, SQLite opened with `SQLITE_OPEN_READONLY`. A write that slipped past the guard is refused by the database. For defense in depth, also give MCP-shared connections a database user with read-only grants.
3. **Policy:** the server is off by default; each connection is shared individually (off by default); 15 s statement timeout, 1000-row and 4 KB-per-cell limits.

Credentials never reach the model: tools return only connection id, name, type, environment and database name, and error messages are scrubbed (`McpRedaction`) of the connection's secrets, URI user info, `password=`-style values and private keys.

**Transport:** the server listens on `127.0.0.1` only, on a random port. Clients connect through `querya-mcp`, which must present a random 256-bit token from an endpoint file readable only by your user (directory `0700`, file `0600`); a wrong token closes the connection. Any process running as your user can read that file, so the MCP server does not protect against an attacker who already controls your session.

**Prompt injection:** query results are data. Text stored in your tables can contain instructions aimed at the model; the server tells clients not to follow them, but the read-only limits above are what actually bound the damage.

**Audit:** every call is logged (Preferences → MCP Server → Recent calls).

## Tests

Automated tests use an **in-memory** secrets backend (see `test/flutter_test_config.dart`) so CI does not require a desktop keyring.


## Archive install limits (extensions and updates)

Marketplace downloads, local extension sideload (`.zip` / `.qext`), and in-app updater extraction use `SafeZipExtractor` (`lib/core/security/safe_zip_extractor.dart`) with shared default limits:

| Limit | Default |
|-------|---------|
| Max compressed archive size | 100 MiB |
| Max total uncompressed size | 500 MiB |
| Max entries | 10 000 |
| Max single entry uncompressed size | 100 MiB |
| Max compression ratio (uncompressed ÷ compressed) | 100:1 |

Archives exceeding these bounds fail closed before files are written to disk. Path traversal checks remain in `archive_path_guard.dart`.

SHA-256 verification for marketplace/sideload streams the file (`sha256.bind(file.openRead())`, same helper as the updater) instead of hashing a full in-memory copy. Zip decode uses a file stream (`InputFileStream`) so the compressed payload is not held as a separate `List<int>` alongside the decoded archive; entry contents are cleared after each write.

## Extension driver OS sandbox

Process-sandbox database drivers launch inside OS-level isolation when available:

| Platform | Wrapper | When unavailable |
|----------|---------|------------------|
| Linux | `bwrap` (bubblewrap) | User must confirm **Run without OS sandbox** |
| macOS | `sandbox-exec` (Seatbelt) | N/A — always wrapped |
| Windows | AppContainer (planned) | User must confirm until native helper ships |

Querya refuses **silent** unsandboxed launch. `SandboxProcessRunner` throws `SandboxOsIsolationUnavailableException` until the user approves via the consent dialog registered from the main window.

**Linux:** install `bubblewrap` and ensure unprivileged user namespaces are enabled if you want OS sandbox without manual confirmation.

## Local extension sideload (`.zip` / `.qext`)

Installing from a local file does **not** verify integrity unless you paste an optional **SHA-256 checksum** in the install dialog. Marketplace installs always require a manifest checksum (#396). Sideload is intended for trusted local packages and development builds.
