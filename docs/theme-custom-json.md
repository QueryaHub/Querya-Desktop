# Querya custom theme JSON (`querya.theme.v1`)

Querya supports two theme file formats:

| Format | Root marker | Import | Docs |
|--------|-------------|--------|------|
| **Querya custom** | `"schema": "querya.theme.v1"` | Planned (theme registry) | this document |
| **VS Code** | `"colors"` object (no `schema`) | **Supported today** | [theme-import.md](theme-import.md) |

VS Code JSON/JSONC import remains fully supported. The custom format is a first-class
Querya schema with explicit `shadcn_colors` and `editor_colors` sections instead of
VS Code workbench key names.

## Purpose

- Ship themes that map directly to Querya runtime models (`ColorScheme`,
  `QueryaEditorTheme`, `QueryaWorkbenchTheme`) without VS Code key indirection.
- Keep theme list scans lightweight: read metadata and color maps as strings; build
  `QueryaTheme` only when a theme is selected.
- Scale to 50+ installed themes with predictable fallback behavior.

Implementation (planned): `lib/core/theme/parser/querya_theme_manifest.dart` and
registry services described in
[theme-parser-implementation-tasks.md](theme-parser-implementation-tasks.md).

## Root object

### Required fields

| Field | Type | Description |
|-------|------|-------------|
| `schema` | string | Must be exactly `querya.theme.v1`. |
| `id` | string | Stable machine id (slug). Used for filenames and settings. Lowercase letters, digits, hyphens recommended. |
| `name` | string | Human-readable label shown in Preferences. |
| `type` | string | `"dark"` or `"light"`. Selects fallback preset (`QueryaTheme.darkDefault` / `QueryaTheme.lightDefault`). |
| `shadcn_colors` | object | String map → shadcn `ColorScheme` tokens. May be `{}`; missing keys fall back to the preset. |
| `editor_colors` | object | String map → editor and workbench tokens. May be `{}`; missing keys fall back to the preset. |

### Optional fields

| Field | Type | Description |
|-------|------|-------------|
| `tokenColors` | array | VS Code–compatible syntax rules (same shape as VS Code themes). Applied to SQL/JSON highlighting. |
| `description` | string | Short summary for theme picker / marketplace. |
| `author` | string | Author or org name. |
| `version` | string | Theme package version (informational). |

Unknown root fields are ignored. In debug builds the parser may log skipped keys.

## Color string formats

All color values are hex strings. The parser reuses `parseVsCodeColor` (via a thin
Querya wrapper) and accepts:

| Format | Example | Notes |
|--------|---------|-------|
| `#RRGGBB` | `"#22D3EE"` | Most common |
| `RRGGBB` | `"22D3EE"` | `#` optional |
| `#RRGGBBAA` | `"#FF22D3EE"` | Alpha last (VS Code style) |
| `RRGGBBAA` | `"FF22D3EE"` | `#` optional |
| `#RGB` | `"#F0A"` | Expanded to `#FF00AA` |
| `#RGBA` | `"#F0A8"` | Expanded to `#FF00AA88` |

Invalid optional color values are **skipped** for that key; the fallback preset value
is used instead. Empty strings are treated as invalid.

## `shadcn_colors` keys

Maps to `shadcn_flutter.ColorScheme` (see `QueryaTheme.colorScheme`).

| Key | Role |
|-----|------|
| `background` | App / page background |
| `foreground` | Primary text |
| `card` | Card surface |
| `cardForeground` | Text on cards |
| `popover` | Popover / dropdown surface |
| `popoverForeground` | Text on popovers |
| `primary` | Primary actions |
| `primaryForeground` | Text on primary |
| `secondary` | Secondary surfaces |
| `secondaryForeground` | Text on secondary |
| `muted` | Muted surfaces |
| `mutedForeground` | Muted labels |
| `accent` | Hover / accent fills |
| `accentForeground` | Text on accent |
| `destructive` | Destructive actions |
| `destructiveForeground` | Text on destructive |
| `border` | Borders |
| `input` | Input borders / fills |
| `ring` | Focus ring |
| `chart1` … `chart5` | Chart palette |

Brightness comes from `type`, not from individual colors.

## `editor_colors` keys

One map feeds both `QueryaEditorTheme` and `QueryaWorkbenchTheme`.

### Editor (syntax surface)

| Key | Target |
|-----|--------|
| `background` | Editor background |
| `foreground` | Default text |
| `lineHighlight` | Current line highlight |
| `selection` | Selection background |
| `lineNumber` | Gutter numbers |
| `bracketMatch` | Matching bracket highlight |
| `widgetBorder` | Editor chrome border |
| `comment` | Comment token (fallback when no `tokenColors` match) |
| `keyword` | Keyword token |
| `string` | String token |
| `number` | Numeric token |
| `operator` | Operator token |
| `function` | Function token |
| `type` | Type name token |

### Workbench (chrome)

| Key | Target |
|-----|--------|
| `canvas` | Main app canvas (title bar, status areas) |
| `surface` | Raised panels, tabs |
| `sidebarBackground` | Explorer / sidebar |
| `editorBackground` | Editor pane chrome (may differ from syntax `background`) |
| `mutedForeground` | Secondary labels |
| `accent` | Brand / focus accent |
| `onAccent` | Text/icons on accent |
| `borderSubtle` | Subtle dividers |
| `destructive` | Error / delete emphasis |
| `success` | Success state |
| `warning` | Warning state |
| `gitModified` | Git modified decoration |
| `gitUntracked` | Git untracked decoration |

If `background` appears without `canvas`, the parser does **not** auto-map it unless
explicitly documented in a future schema revision. Prefer `canvas` and
`editorBackground`.

## `tokenColors`

Same structure as VS Code themes: array of objects with `scope` (string or array),
optional `name`, and `settings.foreground` / `settings.background` / `settings.fontStyle`.

Querya applies these through `TokenStyleResolver` → SQL/JSON highlighters. See
[theme-import.md](theme-import.md) for behavior notes.

## Fallback and error handling

| Situation | Behavior |
|-----------|----------|
| Missing optional color key | Use value from `QueryaTheme.darkDefault` or `QueryaTheme.lightDefault` (based on `type`). |
| Invalid optional color | Skip key; use fallback value. |
| Missing required root field (`schema`, `id`, `name`, `type`, `shadcn_colors`, `editor_colors`) | Parsing fails; theme is not loaded. |
| Wrong `schema` value | Parsing fails. |
| Invalid `type` | Parsing fails. |
| Broken file at startup (selected theme) | App starts with **Querya Dark**; error surfaced in Preferences (planned). User setting is not deleted. |
| Broken file in directory scan | Skipped or shown as disabled in picker (planned); scan does not crash the app. |

## JSONC

Comments and trailing commas are allowed in `.jsonc` files. The shared preprocessor
`stripJsonc` runs before `jsonDecode` (same as VS Code import).

## Minimal example

Only required fields; all colors come from Querya Dark defaults:

```json
{
  "schema": "querya.theme.v1",
  "id": "querya-dark-clone",
  "name": "Querya Dark (minimal)",
  "type": "dark",
  "shadcn_colors": {},
  "editor_colors": {}
}
```

## Full example (dark)

```json
{
  "schema": "querya.theme.v1",
  "id": "cyberpunk-neon",
  "name": "Cyberpunk Neon",
  "type": "dark",
  "description": "Neon cyberpunk preset for Querya workbench and SQL editor.",
  "author": "QueryaHub",
  "version": "1.0.0",
  "shadcn_colors": {
    "background": "#09090B",
    "foreground": "#F8FAFC",
    "card": "#111113",
    "cardForeground": "#F8FAFC",
    "popover": "#111113",
    "popoverForeground": "#F8FAFC",
    "primary": "#00F5FF",
    "primaryForeground": "#020617",
    "secondary": "#18181B",
    "secondaryForeground": "#F8FAFC",
    "muted": "#18181B",
    "mutedForeground": "#94A3B8",
    "accent": "#FF2A6D",
    "accentForeground": "#F8FAFC",
    "destructive": "#EF4444",
    "destructiveForeground": "#F8FAFC",
    "border": "#27272A",
    "input": "#27272A",
    "ring": "#00F5FF",
    "chart1": "#00F5FF",
    "chart2": "#FF2A6D",
    "chart3": "#FCEE09",
    "chart4": "#BD00FF",
    "chart5": "#39FF14"
  },
  "editor_colors": {
    "background": "#0A0A14",
    "foreground": "#E8F4FF",
    "selection": "#FF2A6D44",
    "lineNumber": "#4A3F7A",
    "bracketMatch": "#00F5FF33",
    "widgetBorder": "#00F5FF66",
    "canvas": "#050508",
    "surface": "#14102A",
    "sidebarBackground": "#0C0820",
    "editorBackground": "#0A0A14",
    "mutedForeground": "#8B7CF8",
    "accent": "#00F5FF",
    "onAccent": "#020617",
    "borderSubtle": "#27272A",
    "destructive": "#EF4444",
    "gitModified": "#FCEE09",
    "gitUntracked": "#39FF14"
  },
  "tokenColors": [
    {
      "name": "Comments",
      "scope": ["comment", "comment.line"],
      "settings": { "foreground": "#5C4D8A", "fontStyle": "italic" }
    },
    {
      "name": "Keywords",
      "scope": ["keyword", "keyword.control"],
      "settings": { "foreground": "#FF2A6D", "fontStyle": "bold" }
    },
    {
      "name": "Strings",
      "scope": ["string"],
      "settings": { "foreground": "#FCEE09" }
    }
  ]
}
```

## VS Code format vs Querya custom

| | VS Code JSON/JSONC | Querya custom |
|--|-------------------|---------------|
| Detection | No `schema`; has `colors` | `"schema": "querya.theme.v1"` |
| UI colors | VS Code keys (`editor.background`, `sideBar.background`, …) | `shadcn_colors` + `editor_colors` Querya keys |
| Stable id | File name only | Required `id` field |
| Import today | **Yes** — Preferences → Import theme | Planned via theme registry |
| Syntax tokens | `tokenColors` | `tokenColors` (same) |

To convert a VS Code theme manually, map keys using
[theme-import.md](theme-import.md) and place workbench values into `editor_colors`;
derive shadcn tokens from your palette or leave `{}` to use preset defaults.

## Related docs

- [Theme import (VS Code)](theme-import.md)
- [Theme system overview](theme.md)
- [Implementation plan](theme-parser-implementation-tasks.md)
- Sample VS Code themes: `themes/samples/cyberpunk-neon.json`
