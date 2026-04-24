# Product roadmap (draft)

Living document for planned work. Not a commitment order; adjust as priorities change.

## Query history and favorites

- **Done:** `sql_query_history` in SQLite + record/list APIs; **History** in PostgreSQL / MySQL toolbars; **Preferences → Query history limit** ([`AppSettings.getSqlHistoryMaxEntries`](lib/core/storage/app_settings.dart)).
- **Later:** favorites / pins, opt-out toggle.
- Respect existing **security** model: history stores SQL text only (no passwords); optional opt-out when UI lands.

## Result export

- **Done (small steps):** CSV and JSON from the Data Output grid — copy to clipboard and **Save…** (system dialog): [`ResultsTab`](lib/features/main_screen/results_tab.dart), [`lib/core/csv/`](lib/core/csv/), [`lib/core/json/`](lib/core/json/).
- **Later:** alignment with `AppSettings` max rows for very large grids (warn or truncate before export).

## SSH and advanced networking

- **Today:** the app does not embed SSH tunnels or jump hosts (see [security.md](security.md)).
- **Near term:** expand user-facing docs with recipes: `ssh -L`, cloud provider consoles, VPN.
- **Later (if demand):** optional “local proxy command” or documented integration with external tools; avoid shipping full SSH client scope unless clearly justified.

## Connections tree maintainability

- Continue splitting `connections_panel` library parts as needed; keep behavior and tests green after refactors.

## macOS distribution

- Unsigned builds require extra steps for end users; see [macos-signing.md](macos-signing.md) for a future signing/notarize track.
