# Product roadmap (draft)

Living document for planned work. Not a commitment order; adjust as priorities change.

## Theme system

- **Shipped in 0.4.0 (epic #37):** runtime themes, VS Code `colors` + `tokenColors` import, SQL/JSON
  highlighting, P0 workbench migration, Preferences, tests, docs — [theme.md](theme.md).
- **Shipped in 0.4.1 ([#93](https://github.com/QueryaHub/Querya-Desktop/issues/93)):** UI performance — virtual result grid, lazy connection tree, decoupled scale preview, stats polling, MySQL stats dashboard, local `docker/` dev stack — [perf-baseline.md](perf-baseline.md).
- **Shipped in 0.4.2 (TP-01–TP-30, #96–#125):** custom theme registry — `querya.theme.v1` + VS Code JSON/JSONC scan, Theme picker (50+), import/refresh, built-in Cyberpunk Neon asset, startup fallback, window chrome sync — [theme-custom-json.md](theme-custom-json.md), [theme-import.md](theme-import.md).
- **Shipped in 0.4.3 (TP-F1–TP-F4, #159–#163):** theme folder watcher, marketplace metadata on manifests, visual theme editor with export, HTTPS remote install with checksum — [planned-0.4.3.md](planned-0.4.3.md).
- **Shipped in 0.4.4:** UI motion polish + high refresh rate (90/120/144 Hz), memory and security fixes — [planned-0.4.4.md](planned-0.4.4.md), [motion-and-high-refresh.md](motion-and-high-refresh.md), epic [#170](https://github.com/QueryaHub/Querya-Desktop/issues/170), milestone [0.4.4](https://github.com/QueryaHub/Querya-Desktop/milestone/3).
- **Planned 0.4.5:** SQLite Database Connector — [planned-0.4.5.md](planned-0.4.5.md), milestone [0.4.5](https://github.com/QueryaHub/Querya-Desktop/milestones).
- **Planned 0.4.6+:** Extensions sidebar and marketplace Explore UI — [market-tech.md](market-tech.md).
- **Optional:** Preferences → **Animate theme changes** (off by default).
- **Later:** P2 Mongo/Redis token colors; `re_editor` if perf gap; LSP epic per
  [archive/code-forge-evaluation.md](archive/code-forge-evaluation.md) (**NO-GO** on `code_forge` for 0.3).

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
