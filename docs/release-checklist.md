# Pre-release checklist (release **0.4.11**)

Use this before tagging **`0.4.11`** or running the **Release** workflow.
See [tags-and-releases.md](tags-and-releases.md), [CHANGELOG.md](../CHANGELOG.md), and epic [#341](https://github.com/QueryaHub/Querya-Desktop/issues/341).  
Detailed QA track: issue [#344](https://github.com/QueryaHub/Querya-Desktop/issues/344).

## Product smoke (manual) — 0.4.11

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

## Regression smoke (prior releases)

- [ ] Fresh profile / empty state: create one connection per supported type (PostgreSQL, MySQL, Redis, MongoDB).
- [ ] Reopen the app: connections still appear; **connect** succeeds (secrets migrated or loaded from secure store).
- [ ] Remove a connection: it disappears and reconnect is impossible without re-entering credentials.
- [ ] **Connection → New Database Connection** from the menu saves and shows in the tree.
- [ ] **Driver Manager** shows only built-in drivers (no misleading JDBC requirement).

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

## Automated

- [x] `flutter analyze` — clean (on Linux, if the analyzer crashes with **Too many open files**, try `ulimit -n 8192`; see [CONTRIBUTING.md](../CONTRIBUTING.md)).
- [x] `flutter test` — all green.
- [ ] CI **Flutter version** in `.github/workflows/*.yml` matches the toolchain you validated (bump intentionally when upgrading stable).

## Versioning and release

- [x] `pubspec.yaml` on the release branch is **`0.4.11+N`** (currently **`0.4.11+1`** on `dev` after #346).
- [x] After merge to `main`, confirm any **Auto Version Bump** still yields a **0.4.11+…** product version (do not ship as 0.4.12).
- [x] **Tag** `0.4.11` is placed on the **commit that includes all fixes** you want in binaries (a tag does not auto-include later commits; see [CONTRIBUTING.md](../CONTRIBUTING.md)).
- [x] Run the **Release** workflow from GitHub Actions (see [tags-and-releases.md](tags-and-releases.md)).
- [ ] Verify **portable** zips (`*-linux.zip`, `*-windows.zip`, `*-macos.zip`), **installable** artifacts (`*.AppImage`, `*.deb`, `*.rpm`, `*.flatpak`, `*-windows-setup.exe`), and `SHA256SUMS.txt` on the GitHub Release.

## Docs

- [x] [CHANGELOG.md](../CHANGELOG.md) has a dated **`## [0.4.11]`** section for the release (CI copies it into the GitHub Release body).
- [x] [security.md](security.md) still matches behavior if storage changed.
- [x] [roadmap.md](roadmap.md) marks 0.4.7–0.4.10 shipped and 0.4.11 as the packaging/next release.
