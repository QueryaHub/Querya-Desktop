# Architecture

A high-level map of the codebase for contributors. The app is a Flutter desktop
client with a custom window frame ([bitsdojo_window](https://pub.dev/packages/bitsdojo_window))
and [shadcn_flutter](https://pub.dev/packages/shadcn_flutter) UI components.

## Layered layout

```
lib/
├── main.dart        App entry: window setup, controller bootstrap
├── app/             App shell, theme wiring, global scopes
├── core/            Cross-cutting infrastructure (no feature UI)
├── features/        Feature modules, one folder per area / engine
└── shared/          Reusable widgets shared across features
```

The dependency direction is **features → core/shared**, never the reverse.
`core/` and `shared/` must not import from `features/`.

## `core/`

| Path | Responsibility |
|------|----------------|
| `core/database/` | Engine clients and query execution (PostgreSQL, MySQL, Redis, MongoDB). |
| `core/storage/` | Local SQLite metadata (`local_db.dart`), app settings, secure secrets store. |
| `core/theme/` | Theme tokens, VS Code theme import, color resolution. |
| `core/editor/` | Code editor helpers and syntax highlighting glue. |
| `core/layout/` | Window/dialog sizing and the global UI-scale system. |
| `core/csv/`, `core/json/` | Result export helpers (CSV / JSON). |

## `features/`

| Path | Responsibility |
|------|----------------|
| `features/main_screen/` | Main layout, workspace panel, query/results tabs, history. |
| `features/connections/` | Connection tree, new connection / folder flows, driver manager. |
| `features/postgresql/` | PostgreSQL workspace, object browser, SQL editor dialog. |
| `features/mysql/` | MySQL / MariaDB workspace, browser, SQL editor dialog. |
| `features/redis/` | Redis connection form and workspace. |
| `features/mongodb/` | MongoDB connection form, database dialog, stats view. |
| `features/settings/` | Preferences dialog, controls, interface scale slider. |

## `shared/`

| Path | Responsibility |
|------|----------------|
| `shared/widgets/` | shadcn re-exports, `QueryaDropdown`, app dialog, shared tokens. |

## Cross-cutting systems

- **Theme system** — runtime dark/light/system modes plus VS Code theme import.
  See [theme.md](theme.md) and [theme-import.md](theme-import.md).
- **UI scaling** — a global scale factor propagated via an inherited scope and
  applied to text (`TextScaler`) and dialog dimensions. Lives in `core/layout/`.
- **Secrets** — passwords and connection strings go to the OS secure store, not
  SQLite. See [security.md](security.md).

## Data and secrets

- **Connection metadata + preferences**: local SQLite (`querya.db` in the app
  support directory).
- **Passwords / connection strings**: OS secure store via `flutter_secure_storage`
  (Keychain / Credential Manager / libsecret).

## Tests

Widget tests that touch SQLite or `path_provider` follow the patterns in
`test/features/connections/connections_panel_layout_test.dart` and
`test/flutter_test_config.dart` (in-memory secrets backend, no desktop keyring
required). Run them with `flutter test`.
