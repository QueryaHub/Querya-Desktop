# Pre-release checklist (release **0.4.17**)

Use this before tagging **`0.4.17`** or running the **Release** workflow.
See [tags-and-releases.md](tags-and-releases.md), [CHANGELOG.md](../CHANGELOG.md).
Tracking: [#880](https://github.com/QueryaHub/Querya-Desktop/issues/880). Milestone [0.4.17](https://github.com/QueryaHub/Querya-Desktop/milestone/8).
Manual 120 Hz DevTools QA: issue [#739](https://github.com/QueryaHub/Querya-Desktop/issues/739) (does not block this cut).

## Product smoke (manual) — 0.4.17

- [ ] **Table Browser schema vs PK (#772)** — failed `getTableSchema` shows “schema unavailable”, not “no primary key”; Refresh retries schema.
- [ ] **SQLite implicit rowid (#774)** — `CREATE TABLE t (name TEXT)` Table Browser can Save via `rowid`; `WITHOUT ROWID` stays on declared PK.
- [ ] **Mongo 0-match (#776)** — inspector/JSON Save with a wrong `_id` is Save Failed, not a success toast.
- [ ] **Mongo full-document Save (#778)** — JSON editor Save is `replaceOne`; deleting a nested key in JSON removes it on the server.
- [ ] **Mongo dirty editor Back (#782)** — dirty JSON + breadcrumb Back: discard dialog; Cancel keeps the editor.
- [ ] **Mongo JSON filter (#783)** — `{ "_id": { "$oid": "…" } }` and 24-char hex `_id` match ObjectId documents.
- [ ] **SQL-grid Save** — simple single-table `SELECT` with a PK can Save; JOIN / no-PK stays read-only (Postgres #786, SQLite #795, MySQL #804).
- [ ] **0-row DML (#773)** — Save that matches 0 rows fails and keeps the staging buffer.
- [ ] **Table Browser edit (regression)** — Postgres/MySQL/SQLite table with a PK: double-click cell, Save via DML preview.
- [ ] **Command Palette** — Ctrl/Cmd+P runs a command; Ctrl/Cmd+K jumps to a table.
- [ ] **Mongo field Save** — inspector `$set` still 0-match fails (#776); JSON editor is `replaceOne`.

## Regression smoke (prior releases)

- [ ] Fresh profile / empty state: create one connection per supported type (PostgreSQL, MySQL, Redis, MongoDB, SQLite).
- [ ] Reopen the app: connections still appear; **connect** succeeds (secrets migrated or loaded from secure store).
- [ ] Remove a connection: it disappears and reconnect is impossible without re-entering credentials.
- [ ] **Connection → New Database Connection** from the menu saves and shows in the tree.
- [ ] **Driver Manager** lists built-in drivers + installed sandboxed drivers (no misleading JDBC requirement).
- [ ] **Empty workspace hero** — quick-start actions + recent connections; connect morphs into workspace without hard-cut jank.
- [ ] **Export** — CSV / JSON / Markdown / SQL dump from ResultsTab on a small result set.
- [ ] **Extension table view** — open a sandboxed driver table (or fixture); toolbar filter + export present.
- [ ] **Updater** — Check for Updates / badge sees Latest Release channel correctly after tag.
- [ ] **Fluid shell** — tab strip sliding pill; dialog/dropdown fade-slide; Motion Off snaps (see also [perf-baseline.md](perf-baseline.md) Fluid §).

## Custom themes (manual QA)

Use **Preferences → Appearance** unless noted. Fixtures for copy/import tests live under
`test/fixtures/themes/`; bundled built-in sample: **Querya Cyberpunk Neon** in the theme picker.

- [ ] **Import valid custom dark** — import `test/fixtures/themes/querya_custom_dark.json` (or copy to themes folder). Theme appears in picker; UI uses custom primary (`#38BDF8`).
- [ ] **Import valid custom light** — import `test/fixtures/themes/querya_custom_light.json`. App switches to light brightness; readable text on cards and sidebar.
- [ ] **Import VS Code JSONC** — import `test/fixtures/themes/querya_custom_jsonc.jsonc` or `themes/samples/cyberpunk-neon.jsonc`. Parser accepts comments/trailing commas; theme applies without crash.
- [ ] **Picker with many themes** — install 50+ themes (copy fixtures with unique ids, or duplicate renamed files) → open theme picker: no overflow, list scrolls, search filters rows.
- [ ] **Restart persists selection** — select a registry theme (not only Querya Dark/Light), quit and relaunch: same theme active, no error in Preferences.
- [ ] **Missing file fallback** — with a registry theme selected, delete its file from `{appSupport}/themes/`, restart: app starts on **Querya Dark**, Preferences shows *Selected theme failed to load. Using Querya Dark.*; saved selection id remains until user picks another theme.
- [ ] **Title bar / window controls** — switch Querya Dark, Querya Light, Cyberpunk Neon, and a custom theme: title bar background and minimize/maximize/close hover colors track the active theme.
- [ ] **SQL / JSON syntax** — open SQL editor with a theme that defines `tokenColors` (e.g. cyberpunk sample): comments, keywords, and strings use distinct colors; changing theme updates highlighting after editor refresh.

## Theme follow-ups 0.4.3 (manual QA)

- [ ] **File watcher (TP-F1)** — copy a valid theme JSON into `{appSupport}/themes/` via file manager (no **Refresh themes**): new theme appears in picker within a few seconds.
- [ ] **Marketplace metadata (TP-F2)** — theme with `author` / `tags` in manifest shows subtitle in picker; search matches tag text.
- [ ] **Visual theme editor (TP-F3)** — open **Theme editor**, change a workbench color, confirm live preview; **Export** writes valid `querya.theme.v1` JSON; import exported file applies the same colors.
- [ ] **Remote install (TP-F4)** — **Install from URL…** with a public HTTPS theme JSON (optional SHA-256): theme imports and appears in picker; `http://` or localhost URL is rejected with a clear error.

## Motion and High-Hz 0.4.4 (manual QA)

Verify the 0.4.4 motion tokens, smooth animations, and high refresh rate support:

- [ ] **Motion preferences** — open **Preferences → Appearance**, verify **Motion** option appears.
- [ ] **Motion Full** — set to **Full**, check that all animations run normally.
- [ ] **Motion Reduced** — set to **Reduced**, check that animations are visibly faster (durations cut in half).
- [ ] **Motion Off** — set to **Off**, check that animations complete instantly (0 ms).
- [ ] **OS Reduced Motion** — enable reduced motion in OS settings. The app should automatically disable animations (acting as Off) regardless of in-app Full/Reduced settings (OS setting wins).
- [ ] **Hz diagnostics** — start the app with `--dart-define=QUERYA_REFRESH_OVERLAY=true`. The overlay should display the monitor refresh rate (**Linux: query-only** — compositor decides Hz; see [motion-and-high-refresh.md](motion-and-high-refresh.md)).
- [ ] **High refresh rate smoothness** — verify dialog fade-slide, dropdown show, and tree expand/collapse look smooth at high-Hz (90/120/144 Hz) without jank.
- [ ] Optional: full DevTools pass @ 120 Hz ([#739](https://github.com/QueryaHub/Querya-Desktop/issues/739)).

## Automated

- [ ] `flutter analyze` — clean (on Linux, if the analyzer crashes with **Too many open files**, try `ulimit -n 8192`; see [CONTRIBUTING.md](../CONTRIBUTING.md)).
- [ ] `flutter test` — all green.
- [ ] CI **Flutter version** in `.github/workflows/*.yml` matches the toolchain you validated (bump intentionally when upgrading stable).

## Versioning and release

- [x] `pubspec.yaml` on the 0.4.17 track is **`0.4.17+1`**.
- [ ] After merge to `main`, confirm **Auto Version Bump** yields a **0.4.18+…** placeholder (do not ship binaries as 0.4.18).
- [ ] **Tag** `0.4.17` is placed on the **main merge commit that includes `0.4.17+1`** (not the auto-bump commit).
- [ ] Run the **Release** workflow via that tag (see [tags-and-releases.md](tags-and-releases.md)).
- [ ] Verify **portable** zips (`*-linux.zip`, `*-windows.zip`, `*-macos.zip`), **installable** artifacts (`*.AppImage`, `*.deb`, `*.rpm`, `*.flatpak`, `*-windows-setup.exe`), and `SHA256SUMS.txt` on the GitHub Release.

## Docs

- [x] [CHANGELOG.md](../CHANGELOG.md) has a dated **`## [0.4.17]`** section for the release (CI copies it into the GitHub Release body).
- [x] [security.md](security.md) still matches behavior if storage changed.
- [x] [roadmap.md](roadmap.md) marks 0.4.17 as this cut and 0.5.0 as next.
