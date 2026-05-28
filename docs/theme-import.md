# VS Code theme import (workbench colors)

Querya can apply a **subset** of VS Code theme JSON / JSONC `colors` to
`QueryaWorkbenchTheme`, `QueryaEditorTheme`, and the shadcn `ColorScheme`.

Syntax highlighting (`tokenColors`) is tracked separately (issue #46).

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

## Preferences UI (#43)

In **Preferences → Appearance**:

- **Theme mode** — Dark / Light / System
- **Color preset** — Querya Dark, Querya Light, or imported theme name
- **Import theme…** — pick `.json` / `.jsonc` (VS Code format)
- **Reset appearance** — clears import, overrides, returns to Querya Dark

Imported files are copied to app data (`themes/imported.json`) and survive restarts.

## User overrides (#45)

User customizations are stored as VS Code keys → hex strings in
`theme_overrides_json` (`AppSettings`). Merge order:

```
effectiveColors = merge(importedTheme.colors, userOverrides)
```

Built-in preset defaults apply for keys not present in the merged map.

API: `ThemeController.setWorkbenchColor(key, color?)`,
`ThemeController.clearColorOverrides()` (user layer only).

## Fixtures (tests)

- `test/fixtures/themes/dark_subset.json`
- `test/fixtures/themes/light_subset.json`
- `test/fixtures/themes/with_unknown_keys.json`
