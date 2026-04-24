# Product roadmap (draft)

Living document for planned work. Not a commitment order; adjust as priorities change.

## Query history and favorites

- Persist **recent SQL statements per connection** (or per connection + database) in local SQLite with a configurable cap (e.g. last 50–200 entries).
- UI: dropdown or side panel in SQL workspace to recall, pin “favorites”, and clear history.
- Respect existing **security** model: do not log secrets; optional opt-out.

## Result export

- From results grids (PostgreSQL / MySQL / others): **Export visible page or full result** to CSV and optionally JSON, with a safe row cap aligned with `AppSettings` max rows.
- File picker for save location; desktop-friendly default filename (connection, timestamp).

## SSH and advanced networking

- **Today:** the app does not embed SSH tunnels or jump hosts (see [security.md](security.md)).
- **Near term:** expand user-facing docs with recipes: `ssh -L`, cloud provider consoles, VPN.
- **Later (if demand):** optional “local proxy command” or documented integration with external tools; avoid shipping full SSH client scope unless clearly justified.

## Connections tree maintainability

- Continue splitting `connections_panel` library parts as needed; keep behavior and tests green after refactors.

## macOS distribution

- Unsigned builds require extra steps for end users; see [macos-signing.md](macos-signing.md) for a future signing/notarize track.
