# VS Code theme import (workbench colors)

Querya can apply a **subset** of VS Code theme JSON / JSONC `colors` to
`QueryaWorkbenchTheme`, `QueryaEditorTheme`, and the shadcn `ColorScheme`.

For the native Querya custom format (`querya.theme.v1`), see
**[theme-custom-json.md](theme-custom-json.md)**. Both formats will coexist; VS Code
import remains supported.

Imported `tokenColors` are persisted with the theme file and applied to SQL/JSON
syntax highlighting via `TokenStyleResolver` → `HighlighterTheme` (issue #46).

## Supported `colors` keys

| VS Code key | Querya target |
|-------------|---------------|
| `editor.background` | `workbench.editorBackground`, `editor.background` |
| `editor.foreground` | `editor.foreground`, `ColorScheme.foreground` |
| `editor.selectionBackground` | `editor.selection` |
| `editorLineNumber.foreground` | `editor.lineNumber` |
| `editorBracketMatch.background` | `editor.bracketMatch` |
| `editorWidget.border` | `editor.widgetBorder` (chrome border) |
| `sideBar.background` | `workbench.sidebarBackground` |
| `sideBar.foreground` | `workbench.mutedForeground` |
| `activityBar.background` | `workbench.canvas` |
| `tab.activeBackground` | `workbench.surface` |
| `statusBar.background` | `workbench.canvas` |
| `panel.background` | `workbench.surface` |
| `focusBorder` | `workbench.accent`, `ColorScheme.ring` |
| `input.background` | `workbench.surface` |
| `list.hoverBackground` | `ColorScheme.accent` |
| `gitDecoration.modifiedResourceForeground` | `workbench.gitModified` |
| `gitDecoration.untrackedResourceForeground` | `workbench.gitUntracked` |

Implementation: `lib/core/theme/parser/vscode_color_map.dart`,
`lib/core/theme/parser/querya_theme_from_vscode.dart`.

## Behavior

- **`type`**: `"dark"` or `"light"` in the manifest selects brightness and
  default fallback (`QueryaTheme.darkDefault` / `lightDefault`).
- **Missing keys**: unchanged from the fallback theme.
- **Unknown keys**: ignored; in debug builds a line is printed to the console.
- **Invalid color values**: skipped for that key only.

## Color formats

Hex strings as in VS Code: `#RRGGBB`, `#RRGGBBAA`, `#RGB`, `#RGBA` (see
`parseVsCodeColor`).

## JSONC

Comments and trailing commas are stripped before parse (`stripJsonc`).

## Preferences UI

In **Preferences → Appearance**:

- **Theme mode** — Dark / Light / System
- **Theme** — built-in presets, bundled themes, and themes from the user themes folder
- **Import theme…** — pick `.json` / `.jsonc` and copy into the themes folder
- **Refresh themes** — rescan the themes folder (no live file watcher)
- **Open themes folder** — reveal the app support `themes/` directory in the file manager
- **Reset appearance** — clears overrides and returns to Querya Dark

## Where theme files live

Querya loads themes from the **application support** directory (see
`lib/core/theme/theme_paths.dart`):

| Location | Purpose |
|----------|---------|
| `{appSupport}/themes/` | User-installed themes (`.json`, `.jsonc`) |
| `{appSupport}/themes/imported/` | Legacy import subdirectory (still scanned) |
| `assets/themes/` (bundled) | Built-in themes shipped with the app (e.g. Cyberpunk Neon) |

`{appSupport}` is the OS-specific support folder for Querya Desktop
(`com.example.querya_desktop`). Typical examples:

| OS | Example path |
|----|----------------|
| Linux | `~/.local/share/com.example.querya_desktop/themes` |
| macOS | `~/Library/Application Support/com.example.querya_desktop/themes` |
| Windows | `%APPDATA%\com.example.querya_desktop\themes` |

**Workflow:** copy or import a theme file into `themes/`, then click **Refresh themes**
in Preferences. The app does **not** watch the folder; a restart is not required after
refresh.

**Accepted extensions:** `.json`, `.jsonc` (comments and trailing commas stripped before parse).

**Import via file picker** copies the file into `themes/` (deduplicated by content hash;
duplicate ids get a numeric suffix). Themes picked up from disk use the file basename
(VS Code format) or the `id` field (Querya custom format) as the registry id.

Legacy single-file import (`themes/imported.json` under older builds) is still migrated
into the registry on load when present.

## Troubleshooting

| Symptom | Likely cause | What to do |
|---------|----------------|------------|
| Theme missing from picker after copy | Scan not run or file skipped as invalid | Click **Refresh themes**; verify `.json`/`.jsonc` and valid root object. Debug builds log skipped paths. |
| Import fails immediately | Unsupported file or empty `colors` (VS Code) | Use VS Code theme JSON with a `colors` section, or Querya custom JSON per [theme-custom-json.md](theme-custom-json.md). |
| JSONC import fails | Trailing commas/comments in strict JSON tool | Querya strips JSONC on import; ensure the file still has a single root object after stripping. |
| *Selected theme failed to load. Using Querya Dark.* on startup | Selected file deleted or corrupted | Replace or remove the file; select a working theme. See [theme-custom-json.md](theme-custom-json.md#troubleshooting). |
| Picker slow with many themes | Large registry list | Expected: picker uses `ListView.builder` and search; report regressions if opening Preferences lags with 50+ themes. |
| SQL colors unchanged | Theme has no `tokenColors` | Add VS Code-style `tokenColors` to the file; only imported/registry themes with rules affect syntax highlighting. |
| Title bar wrong color | Window chrome not synced | Switch theme again; file an issue if title bar stays on preset colors with a custom registry theme active. |

## User overrides (#45)

User customizations are stored as VS Code keys → hex strings in
`theme_overrides_json` (`AppSettings`). Merge order:

```
effectiveColors = merge(importedTheme.colors, userOverrides)
```

Built-in preset defaults apply for keys not present in the merged map.

API: `ThemeController.setWorkbenchColor(key, color?)`,
`ThemeController.clearColorOverrides()` (user layer only).

## Remote install from URL (0.4.3+)

**Preferences → Appearance → Install from URL…** downloads a theme over **HTTPS only**
and imports it into `{appSupport}/themes/` using the same deduplication rules as
**Import theme…**.

- Public HTTPS URLs only (no `http://`, no private/loopback hosts in release builds).
- Optional **SHA-256** checksum in the dialog or as `?sha256=` on the URL.
- Invalid JSON or checksum mismatch aborts install; nothing is written to the themes folder.
- No silent background downloads — install runs only after you confirm in the dialog.

Trust model: treat remote theme URLs like any untrusted file; prefer checksums from a
known publisher. Signature verification is not implemented yet.

Implementation: `lib/core/theme/theme_remote_install_service.dart`,
`lib/core/market/marketplace_client.dart` (stub for future Explore UI).

## Sample themes (manual import)

- `themes/samples/cyberpunk-neon.json` — cyberpunk dark preset for UI + SQL/JSON tokens
- `themes/samples/cyberpunk-neon.jsonc` — same, JSONC variant

## Fixtures (tests)

- `test/fixtures/themes/dark_subset.json`
- `test/fixtures/themes/light_subset.json`
- `test/fixtures/themes/with_unknown_keys.json`
