# Product roadmap (draft)

Living document for planned work. Not a commitment order; adjust as priorities change.

**GitHub Latest Release:** [0.4.11](https://github.com/QueryaHub/Querya-Desktop/releases/tag/0.4.11) (2026-07-27).  
**Next patch:** **0.4.11-a** — security review (#395–#402) + Linux rpm/Flatpak/AUR (#386); tag pending.  
**Next product release:** **0.5.0** — live Marketplace download and install — see below.

## Theme system

- **Shipped in 0.4.0 (epic #37):** runtime themes, VS Code `colors` + `tokenColors` import, SQL/JSON
  highlighting, P0 workbench migration, Preferences, tests, docs — [theme.md](theme.md).
- **Shipped in 0.4.1 ([#93](https://github.com/QueryaHub/Querya-Desktop/issues/93)):** UI performance — virtual result grid, lazy connection tree, decoupled scale preview, stats polling, MySQL stats dashboard, local `docker/` dev stack — [perf-baseline.md](perf-baseline.md).
- **Shipped in 0.4.2 (TP-01–TP-30, #96–#125):** custom theme registry — `querya.theme.v1` + VS Code JSON/JSONC scan, Theme picker (50+), import/refresh, built-in Cyberpunk Neon asset, startup fallback, window chrome sync — [theme-custom-json.md](theme-custom-json.md), [theme-import.md](theme-import.md).
- **Shipped in 0.4.3 (TP-F1–TP-F4, #159–#163):** theme folder watcher, marketplace metadata on manifests, visual theme editor with export, HTTPS remote install with checksum — [planned-0.4.3.md](planned-0.4.3.md).
- **Shipped in 0.4.4:** UI motion polish + high refresh rate (90/120/144 Hz), memory and security fixes — [planned-0.4.4.md](planned-0.4.4.md), [motion-and-high-refresh.md](motion-and-high-refresh.md), epic [#170](https://github.com/QueryaHub/Querya-Desktop/issues/170), milestone [0.4.4](https://github.com/QueryaHub/Querya-Desktop/milestone/3).
- **Optional:** Preferences → **Animate theme changes** (off by default; rebuild cost documented in [motion-and-high-refresh.md](motion-and-high-refresh.md) § Theme morph).
- **Later:** P2 Mongo/Redis token colors; `re_editor` if perf gap; LSP epic per
  [archive/code-forge-evaluation.md](archive/code-forge-evaluation.md) (**NO-GO** on `code_forge` for 0.3).

## Desktop releases (0.4.6+)

- **Shipped in 0.4.6:** SQLite Database Connector — [planned-0.4.6.md](planned-0.4.6.md).
- **Shipped in 0.4.7:** Local Extension Discovery — `ExtensionManifest`, local folder scan, theme migration to extension format — [planned-0.4.7.md](planned-0.4.7.md).
- **Shipped in 0.4.8:** Extension Manager UI (+ mock Marketplace) — [planned-0.4.8.md](planned-0.4.8.md).
- **Shipped in 0.4.9:** PostgreSQL SSL & connection reliability — see [CHANGELOG.md](../CHANGELOG.md).
- **Shipped in 0.4.10:** Sandboxed extension runtime (Block E), Plugin RPC bridge (Block C), SDUI form/tree builders, local `.zip`/`.qext` install, Registration/Activation for external database drivers (e.g. ClickHouse), in-app updater — see [CHANGELOG.md](../CHANGELOG.md).
- **Shipped in 0.4.11:** Universal UI / SDUI RPC expand, ExtensionTableView, universal export, MySQL/SQLite parity, shell UX (#339), Fluid QueryaMotion (#342) + perf follow-ups (#356), grid/pool/timeout fixes, dual-channel packaging (portable zip + AppImage / `.deb` / Windows setup) — [CHANGELOG.md](../CHANGELOG.md) `[0.4.11]`, [packaging.md](packaging.md), epic [#379](https://github.com/QueryaHub/Querya-Desktop/issues/379).
- **Pending 0.4.11-a:** security hardening (#395–#402), Linux `.rpm` / Flatpak / AUR (#386) — [CHANGELOG.md](../CHANGELOG.md) `[0.4.11-a]`.
- **Planned 0.5.0:** Marketplace Launch — live download, `sha256` validation, install themes (and later DB drivers) from the network.

## Query history and favorites

- **Done:** `sql_query_history` in SQLite + record/list APIs; **History** in PostgreSQL / MySQL toolbars; **Preferences → Query history limit** ([`AppSettings.getSqlHistoryMaxEntries`](lib/core/storage/app_settings.dart)).
- **Later:** favorites / pins, opt-out toggle.
- Respect existing **security** model: history stores SQL text only (no passwords); optional opt-out when UI lands.

## Result export

- **Done:** CSV, JSON, Markdown, and SQL dump from ResultsTab / table toolbars (0.4.11 candidate, #326) — [`ResultsTab`](lib/features/main_screen/results_tab.dart), [`lib/shared/services/data_export_service.dart`](lib/shared/services/data_export_service.dart).
- **Later:** alignment with `AppSettings` max rows for very large grids (warn or truncate before export).

## SSH and advanced networking

- **Today:** the app does not embed SSH tunnels or jump hosts (see [security.md](security.md)).
- **Near term:** expand user-facing docs with recipes: `ssh -L`, cloud provider consoles, VPN.
- **Later (if demand):** optional “local proxy command” or documented integration with external tools; avoid shipping full SSH client scope unless clearly justified.

## Connections tree maintainability

- Continue splitting `connections_panel` library parts as needed; keep behavior and tests green after refactors.

## macOS distribution

- Unsigned builds require extra steps for end users; see [macos-signing.md](macos-signing.md) for a future signing/notarize track.
