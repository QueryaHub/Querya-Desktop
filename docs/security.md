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
- The app does **not** implement team features, audit logging, or network zero-trust controls.
- **SSH tunnels / jump hosts** are not built into the client today; use OS-level VPN or SSH forwarding if required.

## Tests

Automated tests use an **in-memory** secrets backend (see `test/flutter_test_config.dart`) so CI does not require a desktop keyring.
