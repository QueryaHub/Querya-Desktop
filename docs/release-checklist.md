# Pre-release checklist (release **0.4.4**)

Use this before tagging **`0.4.4`** or running the **Release** workflow.
See [tags-and-releases.md](tags-and-releases.md) and [CHANGELOG.md](../CHANGELOG.md).

## Product smoke (manual)

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
- [ ] **Hz diagnostics** — start the app with `--dart-define=QUERYA_REFRESH_OVERLAY=true`. The overlay should display the correct target refresh rate of the monitor.
- [ ] **High refresh rate smoothness** — verify dialog fade+scale, dropdown show, and tree expand/collapse look extremely smooth at high-Hz (90/120/144 Hz) without jank.

## Automated

- [ ] `flutter analyze` — clean (on Linux, if the analyzer crashes with **Too many open files**, try `ulimit -n 8192`; see [CONTRIBUTING.md](../CONTRIBUTING.md)).
- [ ] `flutter test` — all green.
- [ ] CI **Flutter version** in `.github/workflows/*.yml` matches the toolchain you validated (bump intentionally when upgrading stable).

## Versioning and release

- [ ] `pubspec.yaml` on **`dev`** is **`0.4.1+7`** before merging to `main` (auto version-bump sets **`0.4.4+8`** on `main`).
- [ ] After merge, confirm GitHub Action **Auto Version Bump** committed **`0.4.4+…`** on `main`.
- [ ] **Tag** is placed on the **commit that includes all fixes** you want in binaries (a tag does not auto-include later commits; see [CONTRIBUTING.md](../CONTRIBUTING.md)).
- [ ] Run the **Release** workflow from GitHub Actions (see [tags-and-releases.md](tags-and-releases.md)).
- [ ] Verify **Linux** and **Windows** zip artifacts and `SHA256SUMS.txt` on the GitHub Release.

## Docs

- [ ] [CHANGELOG.md](../CHANGELOG.md) has a **`## [X.Y.Z]`** section for the release version (CI copies it into the GitHub Release body).
- [ ] [security.md](security.md) still matches behavior if storage changed.
- [ ] [roadmap.md](roadmap.md) updated if you are communicating upcoming themes externally.
