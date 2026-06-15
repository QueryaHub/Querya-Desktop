# GitHub Issues: кастомные JSON-темы и масштабирование theme system

Источник: [`theme-parser-implementation-tasks.md`](theme-parser-implementation-tasks.md).  
Формат ниже рассчитан на перенос в GitHub Issues: каждый блок можно заводить как отдельный issue.

## Labels

Рекомендуемые labels:

- `theme`
- `frontend`
- `performance`
- `parser`
- `settings`
- `docs`
- `tests`
- `good first issue` — только для изолированных docs/fixtures/test задач

## Milestones / Epics

- **Epic A — Custom theme parser core**
- **Epic B — Theme registry and caching**
- **Epic C — Preferences theme picker for 50+ themes**
- **Epic D — Built-in themes, filesystem loading, docs**
- **Epic E — Window chrome theme sync**

## Recommended order

1. TP-01 → TP-07: parser core.
2. TP-08 → TP-14: registry, persistence, cache.
3. TP-15 → TP-20: Preferences UI and import flow.
4. TP-21 → TP-24: built-in assets, filesystem folder, docs.
5. TP-25 → TP-27: window chrome sync and final hardening.
6. TP-28 → TP-30: QA, regression tests, release checklist.

---

## TP-01 — Document Querya custom theme JSON schema

**Labels:** `theme`, `docs`, `good first issue`  
**Epic:** A  
**Depends on:** none

### Goal

Create public documentation for the new Querya custom theme JSON format (`querya.theme.v1`) before implementing the parser.

### Context

Current `docs/theme-import.md` describes VS Code theme import. The new format must be documented separately so parser behavior is clear and testable.

### Implementation

Create `docs/theme-custom-json.md` with:

- purpose of the Querya custom format;
- required root fields:
  - `schema`
  - `id`
  - `name`
  - `type`
  - `shadcn_colors`
  - `editor_colors`
- optional root fields:
  - `tokenColors`
  - `description`
  - `author`
  - `version`
- accepted `type` values: `dark`, `light`;
- accepted color formats:
  - `#RRGGBB`
  - `RRGGBB`
  - `#AARRGGBB`
  - `AARRGGBB`
  - optionally `#RGB` / `#RGBA` if supported by existing parser;
- fallback rules:
  - missing optional colors fallback to `QueryaTheme.darkDefault` / `QueryaTheme.lightDefault`;
  - invalid optional color is ignored;
  - missing required root field fails parsing;
  - broken selected theme falls back to Querya Dark on startup;
- difference between VS Code JSON/JSONC and Querya custom JSON;
- one minimal working example and one full example.

Update `docs/theme-import.md` with a short link to `docs/theme-custom-json.md`.

### Acceptance Criteria

- `docs/theme-custom-json.md` exists.
- It includes a valid copy-pastable JSON example.
- It explicitly says VS Code import remains supported.
- It documents fallback/error behavior.

### Tests

Docs only. No automated tests required.

---

## TP-02 — Add custom theme JSON fixtures

**Labels:** `theme`, `tests`, `good first issue`  
**Epic:** A  
**Depends on:** TP-01

### Goal

Add stable fixtures for parser and factory tests.

### Files

- `test/fixtures/themes/querya_custom_dark.json`
- `test/fixtures/themes/querya_custom_light.json`
- `test/fixtures/themes/querya_custom_minimal.json`
- `test/fixtures/themes/querya_custom_invalid_missing_id.json`
- `test/fixtures/themes/querya_custom_invalid_color.json`
- `test/fixtures/themes/querya_custom_jsonc.jsonc`

### Implementation

Add fixtures:

- `querya_custom_dark.json`
  - full dark theme with `shadcn_colors`, `editor_colors`, and sample `tokenColors`;
- `querya_custom_light.json`
  - full light theme;
- `querya_custom_minimal.json`
  - only required root fields and a small set of colors;
- `querya_custom_invalid_missing_id.json`
  - no `id`;
- `querya_custom_invalid_color.json`
  - one optional invalid color and enough valid fields to test skip/failure policy;
- `querya_custom_jsonc.jsonc`
  - comments and trailing commas.

### Acceptance Criteria

- Fixtures are small enough to read in tests.
- Dark/light/minimal fixtures use distinct values so tests can assert mapping.
- Invalid fixtures target one failure mode each.

### Tests

No parser tests in this issue. Fixtures are consumed by later issues.

---

## TP-03 — Add `QueryaThemeManifest` model

**Labels:** `theme`, `parser`  
**Epic:** A  
**Depends on:** TP-02

### Goal

Create an immutable model for Querya custom theme manifests without converting colors to Flutter `Color` yet.

### Files

- `lib/core/theme/parser/querya_theme_manifest.dart`
- `test/core/theme/parser/querya_theme_manifest_test.dart`

### Implementation

Add:

```dart
enum QueryaThemeType { dark, light }

class QueryaThemeManifest {
  const QueryaThemeManifest({
    required this.schema,
    required this.id,
    required this.name,
    required this.type,
    required this.shadcnColors,
    required this.editorColors,
    this.tokenColors = const [],
    this.description,
    this.author,
    this.version,
  });
}

class QueryaThemeManifestParseException implements Exception {
  const QueryaThemeManifestParseException(this.message);
  final String message;
}
```

Fields:

- `schema: String`
- `id: String`
- `name: String`
- `type: QueryaThemeType`
- `shadcnColors: Map<String, String>`
- `editorColors: Map<String, String>`
- `tokenColors: List<TokenColorRule>`
- optional metadata fields.

Add `QueryaThemeManifest.fromJsonString(String raw)`.

Use existing:

- `stripJsonc`
- `TokenColorRule` / existing token color parser path where possible.

### Performance Notes

- Do not create `Color`, `QueryaTheme`, or `ThemeData` here.
- Keep maps unmodifiable.
- Parsing should be pure and synchronous for a single file; async belongs in services.

### Acceptance Criteria

- Valid dark/light fixtures parse.
- JSONC fixture parses.
- Missing required fields throw `QueryaThemeManifestParseException`.
- Unknown fields are ignored.
- Returned maps are immutable or safely copied.

### Tests

Cover:

- valid full dark;
- valid full light;
- minimal manifest;
- JSONC comments/trailing commas;
- missing `id`;
- invalid `type`;
- empty `shadcn_colors` / `editor_colors` behavior according to docs.

---

## TP-04 — Add Querya theme color parser wrapper

**Labels:** `theme`, `parser`, `tests`  
**Epic:** A  
**Depends on:** TP-03

### Goal

Support Querya custom HEX formats without duplicating incompatible color parsing logic.

### Files

- `lib/core/theme/parser/color_parser.dart`
- `test/core/theme/parser/color_parser_test.dart`

### Implementation

Add:

```dart
Color parseQueryaThemeColor(String raw)
```

Behavior:

- trim whitespace;
- accept `#RRGGBB`;
- accept `RRGGBB`;
- accept `#AARRGGBB`;
- accept `AARRGGBB`;
- delegate to `parseVsCodeColor` where possible;
- throw `FormatException` for invalid input.

If current `parseVsCodeColor` already supports all formats, implement this wrapper as normalization + delegate.

### Acceptance Criteria

- Wrapper exists and is used by custom theme factory.
- No second unrelated parser implementation.
- Error messages mention the invalid value.

### Tests

Cases:

- `#1E1E1E`
- `1E1E1E`
- `#FF1E1E1E`
- `FF1E1E1E`
- lowercase hex
- invalid length
- invalid characters
- empty string

---

## TP-05 — Map `shadcn_colors` to `ColorScheme`

**Labels:** `theme`, `parser`  
**Epic:** A  
**Depends on:** TP-04

### Goal

Convert custom `shadcn_colors` into `shadcn_flutter.ColorScheme` with fallback values.

### Files

- `lib/core/theme/parser/querya_theme_color_scheme.dart`
- `test/core/theme/parser/querya_theme_color_scheme_test.dart`

### Implementation

Add pure function:

```dart
ColorScheme colorSchemeFromQueryaThemeColors({
  required Map<String, String> colors,
  required QueryaTheme fallback,
});
```

Map these keys:

- `background`
- `foreground`
- `card`
- `cardForeground`
- `popover`
- `popoverForeground`
- `primary`
- `primaryForeground`
- `secondary`
- `secondaryForeground`
- `muted`
- `mutedForeground`
- `accent`
- `accentForeground`
- `destructive`
- `destructiveForeground`
- `border`
- `input`
- `ring`
- `chart1`
- `chart2`
- `chart3`
- `chart4`
- `chart5`

Fallback:

- missing key -> fallback `colorScheme` value;
- invalid optional color -> fallback value;
- debug log invalid optional key if useful.

### Acceptance Criteria

- Function is pure.
- Missing optional keys preserve fallback.
- Full fixture maps distinct expected values.
- Brightness comes from fallback theme, not from colors map.

### Tests

- full map uses custom values;
- missing keys use fallback;
- invalid optional color uses fallback;
- chart colors fallback correctly.

---

## TP-06 — Map `editor_colors` to `QueryaEditorTheme`

**Labels:** `theme`, `parser`  
**Epic:** A  
**Depends on:** TP-04

### Goal

Convert custom editor color tokens into `QueryaEditorTheme`.

### Files

- `lib/core/theme/parser/querya_editor_theme_from_manifest.dart`
- `test/core/theme/parser/querya_editor_theme_from_manifest_test.dart`

### Implementation

Add:

```dart
QueryaEditorTheme editorThemeFromQueryaColors({
  required Map<String, String> colors,
  required QueryaEditorTheme fallback,
});
```

Support keys matching current `QueryaEditorTheme` fields. At minimum:

- `background`
- `foreground`
- `selection`
- `lineNumber`
- `bracketMatch`
- `widgetBorder`

If `QueryaEditorTheme` has additional fields, include them explicitly.

Fallback:

- missing/invalid key -> fallback field.

### Acceptance Criteria

- Full fixture changes editor background/foreground/selection.
- Minimal fixture falls back for missing fields.
- Invalid optional color does not crash.

### Tests

- full custom values;
- fallback behavior;
- invalid optional value.

---

## TP-07 — Map `editor_colors` to `QueryaWorkbenchTheme`

**Labels:** `theme`, `parser`  
**Epic:** A  
**Depends on:** TP-04

### Goal

Convert workbench-related custom tokens into `QueryaWorkbenchTheme`.

### Files

- `lib/core/theme/parser/querya_workbench_theme_from_manifest.dart`
- `test/core/theme/parser/querya_workbench_theme_from_manifest_test.dart`

### Implementation

Add:

```dart
QueryaWorkbenchTheme workbenchThemeFromQueryaColors({
  required Map<String, String> colors,
  required QueryaWorkbenchTheme fallback,
});
```

Support keys:

- `sidebarBackground`
- `canvas`
- `surface`
- `editorBackground`
- `mutedForeground`
- `accent`
- `onAccent`
- `borderSubtle`
- `destructive`
- `gitModified`
- `gitUntracked`

If the docs use `background`, map it deliberately:

- `background` -> `canvas` and/or `editorBackground` only if explicit in docs.

### Acceptance Criteria

- Mapping is documented in code comments or docs table.
- Missing keys use fallback.
- Invalid optional colors use fallback.

### Tests

- full custom workbench mapping;
- minimal fallback;
- invalid optional value.

---

## TP-08 — Build `QueryaTheme` from custom manifest

**Labels:** `theme`, `parser`  
**Epic:** A  
**Depends on:** TP-05, TP-06, TP-07

### Goal

Provide one factory that converts `QueryaThemeManifest` into the existing app-level `QueryaTheme`.

### Files

- `lib/core/theme/parser/querya_theme_from_manifest.dart`
- `test/core/theme/parser/querya_theme_from_manifest_test.dart`

### Implementation

Add:

```dart
QueryaTheme queryaThemeFromManifest(QueryaThemeManifest manifest)
```

Algorithm:

1. Pick fallback:
   - dark -> `QueryaTheme.darkDefault`
   - light -> `QueryaTheme.lightDefault`
2. Build `ColorScheme` from `shadcn_colors`.
3. Build `QueryaEditorTheme` from `editor_colors`.
4. Build `QueryaWorkbenchTheme` from `editor_colors`.
5. Return `fallback.copyWith(...)`.
6. Preserve `tokenColors`.

### Acceptance Criteria

- Full dark fixture creates dark `QueryaTheme`.
- Full light fixture creates light `QueryaTheme`.
- `tokenColors` are preserved.
- No `ThemeData` is created.

### Tests

- dark brightness;
- light brightness;
- shadcn color mapping;
- editor/workbench mapping;
- token colors preserved;
- minimal fixture fallback.

---

## TP-09 — Add typed theme load result

**Labels:** `theme`, `parser`, `error-handling`  
**Epic:** A  
**Depends on:** TP-08

### Goal

Introduce result types for loading/parsing themes so UI and startup can handle failures without exceptions leaking.

### Files

- `lib/core/theme/theme_load_result.dart`

### Implementation

Add sealed result:

```dart
sealed class ThemeLoadResult {
  const ThemeLoadResult();
}

class ThemeLoadSuccess extends ThemeLoadResult {
  const ThemeLoadSuccess({
    required this.definition,
    required this.theme,
  });
}

class ThemeLoadFailure extends ThemeLoadResult {
  const ThemeLoadFailure({
    required this.definition,
    required this.message,
    this.error,
  });
}
```

Use this result in later registry APIs.

### Acceptance Criteria

- Result can represent success/failure without throwing.
- Failure keeps enough data to show user-facing error and debug logs.

### Tests

No direct tests required unless lint coverage demands it. Later registry tests will cover usage.

---

## TP-10 — Add `ThemeDefinition`

**Labels:** `theme`, `registry`  
**Epic:** B  
**Depends on:** TP-03

### Goal

Represent lightweight theme metadata for lists/pickers without full parsing.

### Files

- `lib/core/theme/theme_definition.dart`
- `test/core/theme/theme_definition_test.dart`

### Implementation

Add:

```dart
enum ThemeSource { builtin, imported, filesystem, legacyImported }
enum ThemeFormat { queryaCustom, vscode }

class ThemeDefinition {
  const ThemeDefinition({
    required this.id,
    required this.name,
    required this.source,
    required this.format,
    required this.isDark,
    this.path,
    this.lastModified,
    this.contentHash,
  });
}
```

Add helpers:

- `bool get isFileBacked`
- `String get stableCacheKey`

### Acceptance Criteria

- `ThemeDefinition` is immutable.
- `stableCacheKey` changes when `contentHash` changes.
- Does not depend on Flutter widgets.

### Tests

- file-backed vs builtin;
- cache key includes id/hash/source;
- equality if implemented.

---

## TP-11 — Add theme paths helper

**Labels:** `theme`, `filesystem`  
**Epic:** B  
**Depends on:** TP-10

### Goal

Centralize app theme directories and avoid path logic scattered across services.

### Files

- `lib/core/theme/theme_paths.dart`
- `test/core/theme/theme_paths_test.dart` if path provider can be faked easily.

### Implementation

Add:

```dart
abstract final class ThemePaths {
  static Future<Directory> userThemesDirectory();
  static Future<Directory> importedThemesDirectory();
}
```

Rules:

- Primary user dir: app support directory + `themes`.
- Imported dir: app support directory + `themes/imported`.
- Optionally expose `legacyDotQueryaThemesDirectory()` for later `~/.querya/themes`.

### Acceptance Criteria

- Directories are not created by path getter unless method name says `ensure`.
- Separate `ensureUserThemesDirectory()` can create it.

### Tests

- If existing test support fakes path provider, assert paths.
- Otherwise cover through registry tests.

---

## TP-12 — Implement filesystem theme scan

**Labels:** `theme`, `filesystem`, `performance`  
**Epic:** B  
**Depends on:** TP-10, TP-11

### Goal

Scan app support theme folder and return lightweight `ThemeDefinition` objects.

### Files

- `lib/core/theme/theme_registry_service.dart`
- `test/core/theme/theme_registry_service_test.dart`

### Implementation

Add:

```dart
class ThemeRegistryService {
  Future<List<ThemeDefinition>> loadThemeDefinitions();
}
```

For `.json` and `.jsonc` files:

1. Read file async.
2. Detect format:
   - if root `schema == querya.theme.v1` -> custom;
   - otherwise try VS Code manifest.
3. Extract only metadata:
   - id
   - name
   - type/isDark
   - format
   - path
   - lastModified
   - contentHash
4. Skip broken files from list or return a disabled/error definition. Prefer disabled/error definition if UI should show it later.

### Performance Notes

- Do not construct `QueryaTheme`.
- Do not construct `ThemeData`.
- Hash file content once during scan.
- Async file IO only.

### Acceptance Criteria

- Valid custom files appear.
- Valid VS Code files appear.
- Broken file does not crash scan.
- Only `.json` / `.jsonc` are considered.

### Tests

- temp dir with 2 valid themes and 1 broken;
- stable ordering by name;
- content hash changes when file changes.

---

## TP-13 — Load selected theme by definition

**Labels:** `theme`, `registry`  
**Epic:** B  
**Depends on:** TP-12, TP-09

### Goal

Given a `ThemeDefinition`, parse the full theme and return `ThemeLoadResult`.

### Files

- `lib/core/theme/theme_registry_service.dart`
- `test/core/theme/theme_registry_service_test.dart`

### Implementation

Add:

```dart
Future<ThemeLoadResult> loadTheme(ThemeDefinition definition)
```

Behavior:

- `ThemeFormat.queryaCustom` -> `QueryaThemeManifest.fromJsonString` -> `queryaThemeFromManifest`.
- `ThemeFormat.vscode` -> existing `VsCodeThemeManifest` -> existing `queryaThemeFromVsCode`.
- failure -> `ThemeLoadFailure`.
- missing file -> `ThemeLoadFailure`.

### Acceptance Criteria

- Custom definition loads to `QueryaTheme`.
- VS Code definition still loads.
- Missing/deleted file returns failure.
- No app crash on parse failure.

### Tests

- custom success;
- VS Code success using existing fixture;
- deleted file failure;
- invalid file failure.

---

## TP-14 — Add LRU cache for parsed themes

**Labels:** `theme`, `performance`, `registry`  
**Epic:** B  
**Depends on:** TP-13

### Goal

Avoid repeated file reads and parsing when switching between themes.

### Files

- `lib/core/theme/theme_registry_service.dart`
- `test/core/theme/theme_registry_cache_test.dart`

### Implementation

Inside `ThemeRegistryService`:

- cache `QueryaTheme` by `definition.stableCacheKey`;
- max entries: 12 or 20;
- on cache hit, return cached theme;
- on content hash change, key changes naturally;
- expose `clearCache()` for tests/reset.

If current project has no LRU helper, implement tiny private LRU using `LinkedHashMap`.

### Acceptance Criteria

- Loading same definition twice parses once.
- Loading changed file parses again.
- Cache evicts oldest entry after limit.

### Tests

- fake parser counter or temp file mutation;
- cache hit;
- cache invalidation by hash;
- eviction.

---

## TP-15 — Persist selected theme id/path in AppSettings

**Labels:** `theme`, `storage`  
**Epic:** B  
**Depends on:** TP-10

### Goal

Persist selected registry theme across restarts without storing heavy objects.

### Files

- `lib/core/storage/app_settings.dart`
- `test/core/storage/app_settings_test.dart`

### Implementation

Add keys:

- `theme_selected_id`
- `theme_selected_source`
- `theme_selected_path`

Add methods:

```dart
Future<String?> getSelectedThemeId();
Future<void> setSelectedThemeId(String? id);
Future<String?> getSelectedThemeSource();
Future<void> setSelectedThemeSource(String? source);
Future<String?> getSelectedThemePath();
Future<void> setSelectedThemePath(String? path);
```

Keep existing preset/imported settings unchanged.

### Acceptance Criteria

- Settings roundtrip.
- Clearing selected theme works.
- No SQL workspace revision bump unless existing theme settings already do that intentionally.

### Tests

- id/source/path roundtrip;
- clear values;
- existing theme preset tests still pass.

---

## TP-16 — Migrate legacy imported theme into registry

**Labels:** `theme`, `migration`, `compatibility`  
**Epic:** B  
**Depends on:** TP-12, TP-15

### Goal

Users with existing imported VS Code themes should keep them after registry lands.

### Files

- `lib/core/theme/theme_registry_service.dart`
- `lib/core/theme/theme_import_service.dart`
- `lib/core/theme/theme_controller.dart`
- tests as needed.

### Implementation

During registry load:

- check existing persisted import path/name/colors;
- if found, add a `ThemeDefinition`:
  - `id: legacy-imported` or `imported`;
  - `source: legacyImported`;
  - `format: vscode`;
  - `path: stored import file`;
  - `name: importedThemeName ?? "Imported theme"`.

Do not delete old settings.

### Acceptance Criteria

- Existing `QueryaThemePreset.imported` still applies.
- Legacy imported theme appears in new picker.
- Missing legacy file falls back gracefully.

### Tests

- fake old imported path -> registry definition exists;
- selected legacy imported theme loads;
- missing old file does not crash.

---

## TP-17 — Integrate registry into ThemeController load

**Labels:** `theme`, `controller`  
**Epic:** B  
**Depends on:** TP-13, TP-15, TP-16

### Goal

Make `ThemeController` aware of registry themes while preserving existing presets.

### Files

- `lib/core/theme/theme_controller.dart`
- `lib/core/theme/querya_theme_preset.dart`
- tests for theme controller.

### Implementation

Add state:

- `_availableThemes: List<ThemeDefinition>`
- `_selectedThemeId: String?`
- `_selectedThemePath: String?`
- `_selectedThemeLoadError: String?`

Add getters:

- `availableThemes`
- `selectedThemeId`
- `selectedThemeLoadError`

Add methods:

```dart
Future<void> loadAvailableThemes();
Future<void> setThemeById(String id);
Future<ThemeLoadResult> previewThemeById(String id);
```

Behavior:

- `load()` first loads existing mode/preset.
- Then load registry definitions async.
- If stored selected id exists, try load it.
- On failure, apply Querya Dark fallback but keep error visible.

### Performance Notes

- Do not call `notifyListeners()` for every discovered file.
- Batch registry load and notify once.
- `previewThemeById` must not mutate active app theme.

### Acceptance Criteria

- Existing `setPreset()` behavior still works.
- New `setThemeById()` applies registry theme.
- Broken selected theme falls back to Querya Dark.
- `previewThemeById()` returns theme/result without notifying app listeners.

### Tests

- old presets still pass;
- select by id persists setting;
- preview does not change `activeTheme`;
- broken selected id fallback.

---

## TP-18 — Add `ThemePickerButton` widget shell

**Labels:** `theme`, `settings`, `frontend`  
**Epic:** C  
**Depends on:** TP-10

### Goal

Introduce a dedicated picker UI for many themes instead of overloading a small dropdown.

### Files

- `lib/features/settings/theme_picker_button.dart`
- `test/features/settings/theme_picker_button_test.dart`

### Implementation

Create widget:

```dart
class ThemePickerButton extends StatelessWidget {
  const ThemePickerButton({
    required this.themes,
    required this.selectedThemeId,
    required this.onSelected,
    this.isLoading = false,
  });
}
```

Use:

- `MenuAnchor`;
- fixed/max popup height 300-360px;
- `Scrollbar`;
- `ListView.builder`;
- row shows:
  - name;
  - source badge;
  - dark/light icon or label.

### Acceptance Criteria

- Opens menu with 50+ fake themes without overflow.
- Uses builder list, not `Column(children: themes.map(...))`.
- Does not parse or apply theme during build.

### Tests

- pump with 60 definitions;
- open menu;
- visible rows render;
- no exception/overflow in test logs if test harness supports it;
- tap row triggers `onSelected(id)`.

---

## TP-19 — Add search/filter to ThemePickerButton

**Labels:** `theme`, `settings`, `frontend`  
**Epic:** C  
**Depends on:** TP-18

### Goal

Make 50+ themes easy to navigate.

### Files

- `lib/features/settings/theme_picker_button.dart`
- `test/features/settings/theme_picker_button_test.dart`

### Implementation

Inside popup:

- small search input at top;
- local `TextEditingController`;
- filter by lowercase `name`, `id`, `source`;
- debounce not strictly required for 50 items, but avoid parsing/building themes;
- dispose controller.

### Acceptance Criteria

- Typing filters list.
- Empty result shows small message.
- Search does not call `ThemeController.setThemeById`.

### Tests

- filter by theme name;
- filter no results;
- clear input restores list.

---

## TP-20 — Add safe preview card without applying theme on hover

**Labels:** `theme`, `settings`, `performance`  
**Epic:** C  
**Depends on:** TP-18, TP-17

### Goal

Optional visual preview for hovered/selected theme without rebuilding the whole app.

### Files

- `lib/features/settings/theme_preview_card.dart`
- `lib/features/settings/theme_picker_button.dart`
- tests as needed.

### Implementation

Add `ThemePreviewCard`:

- accepts `QueryaTheme` or lightweight preview colors;
- displays:
  - background;
  - surface;
  - primary/accent;
  - sample text;
  - editor background strip.

In picker:

- hover selects preview target id locally;
- debounce 100-150ms before calling `previewThemeById`;
- preview result stored in local state only;
- never call `setThemeById` on hover.

### Acceptance Criteria

- Hovering row does not change app theme.
- Preview card updates after debounce.
- Broken preview shows non-blocking error in card.

### Tests

- hover/callback does not call `onSelected`;
- preview future resolves and card updates;
- broken preview shows fallback/error.

---

## TP-21 — Wire ThemePickerButton into Preferences

**Labels:** `theme`, `settings`, `frontend`  
**Epic:** C  
**Depends on:** TP-17, TP-18

### Goal

Replace or extend current Color preset dropdown with registry-backed theme selection.

### Files

- `lib/features/settings/preferences_appearance_section.dart`
- `lib/features/settings/theme_picker_button.dart`

### Implementation

In Appearance:

- keep `Theme mode`;
- replace `Color preset` row with `Theme` row using `ThemePickerButton`;
- include existing Querya Dark/Light as built-in definitions;
- show current imported/registry selected theme;
- call `ThemeController.setThemeById(id)` on select;
- keep old `Import theme…` and `Reset appearance` buttons.

### Compatibility

- If registry unavailable/empty, fallback to current preset dropdown behavior or show Querya Dark/Light only.

### Acceptance Criteria

- Querya Dark/Light selectable.
- Legacy imported theme selectable if present.
- Selecting registry theme applies immediately.
- Existing reset returns to Querya Dark.

### Tests

- widget shows built-in themes;
- selecting theme calls controller hook or fake callback;
- reset remains visible;
- import button remains visible.

---

## TP-22 — Add refresh themes action in Preferences

**Labels:** `theme`, `settings`, `filesystem`  
**Epic:** C  
**Depends on:** TP-17, TP-21

### Goal

Let users refresh filesystem themes without restarting the app.

### Files

- `lib/features/settings/preferences_appearance_section.dart`
- `lib/core/theme/theme_controller.dart`

### Implementation

Add button near import/reset:

- `Refresh themes`
- calls `ThemeController.loadAvailableThemes()`;
- shows small loading state;
- preserves active theme if still available;
- if active theme changed on disk, optionally reload when selected again, not immediately.

### Acceptance Criteria

- Refresh updates list.
- Broken files do not break Preferences.
- Loading state does not block whole dialog.

### Tests

- fake controller list changes after refresh;
- button disabled while refreshing.

---

## TP-23 — Import custom themes into user themes directory

**Labels:** `theme`, `filesystem`, `settings`  
**Epic:** D  
**Depends on:** TP-12, TP-21

### Goal

Make `Import theme…` add themes to registry instead of only overwriting one `imported.json`.

### Files

- `lib/core/theme/theme_registry_service.dart`
- `lib/core/theme/theme_import_service.dart`
- `lib/features/settings/preferences_appearance_section.dart`

### Implementation

Add:

```dart
Future<ThemeDefinitionImportResult> importThemeFile(String sourcePath)
```

Behavior:

- detect Querya custom vs VS Code;
- validate;
- copy into app support themes directory;
- filename should be stable and safe:
  - `${id}.json` for custom;
  - slugified name for VS Code;
- avoid overwrite:
  - if same id/hash exists, reuse;
  - if same id different hash, append suffix or replace only after explicit policy;
- return new `ThemeDefinition`.

### Acceptance Criteria

- Importing custom theme adds it to picker.
- Importing VS Code theme still works.
- Multiple imported themes can coexist.
- Old single imported flow still works until fully migrated.

### Tests

- import custom;
- import VS Code;
- duplicate import same hash;
- duplicate id different content.

---

## TP-24 — Add built-in theme assets

**Labels:** `theme`, `assets`, `docs`  
**Epic:** D  
**Depends on:** TP-12

### Goal

Ship built-in sample themes in release builds, not only as repository files.

### Files

- `assets/themes/`
- `pubspec.yaml`
- `lib/core/theme/theme_registry_service.dart`
- tests as feasible.

### Implementation

Move/copy curated themes to:

- `assets/themes/cyberpunk-neon.json`
- any other approved built-in themes.

Update `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/themes/
```

Registry:

- load built-in asset manifest;
- create `ThemeDefinition(source: ThemeSource.builtin)`;
- load full theme from asset when selected.

### Acceptance Criteria

- Built-in themes show in picker in release/profile builds.
- App does not depend on repo `themes/samples/` path at runtime.
- Existing `themes/samples/` can remain for docs/manual testing.

### Tests

- Asset loading if test environment supports bundle.
- Otherwise unit-test parsing with same file content.

---

## TP-25 — Add user theme folder docs and open-folder affordance

**Labels:** `theme`, `docs`, `settings`  
**Epic:** D  
**Depends on:** TP-11, TP-21

### Goal

Make filesystem themes discoverable.

### Files

- `docs/theme-custom-json.md`
- `docs/theme-import.md`
- `lib/features/settings/preferences_appearance_section.dart`

### Implementation

Docs:

- show actual app support path behavior;
- mention accepted extensions;
- mention refresh/restart.

UI:

- show hint text:
  - "Themes are loaded from app support themes folder."
- optional button:
  - `Open themes folder`
  - can be follow-up if cross-platform opening helper does not exist.

### Acceptance Criteria

- User can understand where to put downloaded themes.
- UI does not promise watcher/live reload if not implemented.

### Tests

Docs only unless adding button.

---

## TP-26 — Sync custom window chrome with active theme

**Labels:** `theme`, `frontend`, `bitsdojo`  
**Epic:** E  
**Depends on:** TP-17

### Goal

Ensure title bar / window controls follow custom theme background/canvas.

### Files

- `lib/main.dart`
- `lib/features/main_screen/main_screen.dart`
- any title bar/window button widgets.

### Implementation

Find where `bitsdojo_window` title area and window controls are styled.

Use:

- `QueryaThemeScope.of(context).workbench.canvas`
- `QueryaThemeScope.of(context).workbench.surface`
- `QueryaThemeScope.of(context).workbench.mutedForeground`

Avoid:

- direct singleton reads inside deep widgets when inherited theme is available;
- app-wide notify on hover.

### Acceptance Criteria

- Switching theme updates title bar background.
- Window buttons remain readable.
- Hover states use theme tokens.

### Tests

- Widget test if title bar is testable.
- Otherwise manual smoke checklist in PR body:
  - dark;
  - light;
  - custom dark;
  - custom light.

---

## TP-27 — Startup fallback for missing/broken selected theme

**Labels:** `theme`, `error-handling`, `stability`  
**Epic:** E  
**Depends on:** TP-17

### Goal

Prevent broken custom themes from breaking app startup.

### Files

- `lib/core/theme/theme_controller.dart`
- tests for controller.

### Implementation

On `ThemeController.load()`:

1. Read selected theme id/path.
2. Try registry load.
3. If failure:
   - set active theme to Querya Dark;
   - keep `selectedThemeLoadError`;
   - do not crash;
   - do not delete user setting automatically.
4. Preferences can show:
   - "Selected theme failed to load. Using Querya Dark."

### Acceptance Criteria

- Missing selected file starts app with Querya Dark.
- Invalid selected file starts app with Querya Dark.
- Error visible in Preferences.
- User can choose another theme and clear error.

### Tests

- missing file;
- invalid file;
- subsequent valid selection clears error.

---

## TP-28 — Performance test: 50+ themes in picker

**Labels:** `theme`, `performance`, `tests`  
**Epic:** E  
**Depends on:** TP-18, TP-21

### Goal

Prevent regression where many themes make Preferences slow or overflow.

### Files

- `test/features/settings/theme_picker_button_test.dart`
- maybe `test/features/settings/preferences_appearance_section_test.dart`

### Implementation

Create 60 fake `ThemeDefinition` objects.

Test:

- picker opens;
- only visible subset is built if measurable;
- no overflow exception;
- scroll to bottom works;
- select last item works.

If exact build count is hard to assert, assert behavior and no exceptions.

### Acceptance Criteria

- Test fails if picker uses unbounded `Column` and overflows.
- Test passes with `ListView.builder`.

---

## TP-29 — End-to-end theme import test

**Labels:** `theme`, `tests`, `integration`  
**Epic:** E  
**Depends on:** TP-21, TP-23

### Goal

Cover the full import/select path with a fake filesystem theme.

### Files

- `test/features/settings/theme_import_flow_test.dart`

### Implementation

Use fake/temp app support path if project test support allows it.

Flow:

1. Put custom JSON in temp source.
2. Import through service/controller.
3. Registry list includes it.
4. Select it.
5. `ThemeController.activeTheme` changes expected token.
6. Restart-like reload preserves selection.

### Acceptance Criteria

- Custom theme can be imported, selected, and restored.
- Test does not depend on real user home directory.

---

## TP-30 — Release docs and QA checklist for custom themes

**Labels:** `theme`, `docs`, `qa`  
**Epic:** E  
**Depends on:** TP-01 through TP-29

### Goal

Prepare the feature for release and manual verification.

### Files

- `docs/theme-custom-json.md`
- `docs/theme-import.md`
- `docs/release-checklist.md`
- `CHANGELOG.md` when release branch is prepared.

### Implementation

Add QA checklist:

- import valid custom dark;
- import valid custom light;
- import VS Code JSONC;
- select among 50+ fake themes or test pack;
- restart app and verify selected theme persists;
- delete selected theme file and restart;
- verify fallback + Preferences error;
- verify title bar/window controls colors;
- verify SQL/JSON highlighting still uses tokenColors.

### Acceptance Criteria

- Release checklist includes custom theme scenarios.
- Docs include troubleshooting for invalid colors/missing fields.
- CHANGELOG entry can be written from completed issues.

---

## Optional follow-up issues

These are intentionally out of the first implementation pass (**shipped in 0.4.2**).
**Shipped in 0.4.3** ([milestone](https://github.com/QueryaHub/Querya-Desktop/milestone/2), epic **#159**) — see [planned-0.4.3.md](planned-0.4.3.md).

### TP-F1 — File watcher for user themes folder ([#160](https://github.com/QueryaHub/Querya-Desktop/issues/160))

Use a filesystem watcher to auto-refresh themes after files are added/removed. Keep as follow-up because watchers differ by OS and can introduce lifecycle bugs.

### TP-F2 — Theme marketplace metadata ([#161](https://github.com/QueryaHub/Querya-Desktop/issues/161))

Support metadata fields like preview image, tags, homepage, license. Useful only after custom theme format is stable.

### TP-F3 — Visual theme editor ([#162](https://github.com/QueryaHub/Querya-Desktop/issues/162))

Allow editing theme colors in Preferences and export to `querya.theme.v1`. This is larger than parser/import support.

### TP-F4 — Remote theme install ([#163](https://github.com/QueryaHub/Querya-Desktop/issues/163))

Install theme from URL. Requires network, trust/security decisions, and probably signature/checksum policy.

## Master checklist

- [x] TP-01 docs schema
- [x] TP-02 fixtures
- [x] TP-03 manifest model
- [x] TP-04 color parser wrapper
- [x] TP-05 shadcn color scheme mapping
- [x] TP-06 editor theme mapping
- [x] TP-07 workbench theme mapping
- [x] TP-08 QueryaTheme factory
- [x] TP-09 load result types
- [x] TP-10 ThemeDefinition
- [x] TP-11 theme paths
- [x] TP-12 filesystem scan
- [x] TP-13 load selected definition
- [x] TP-14 parsed theme cache
- [x] TP-15 AppSettings selected theme
- [x] TP-16 legacy imported migration
- [x] TP-17 ThemeController registry integration
- [x] TP-18 ThemePickerButton shell
- [x] TP-19 picker search/filter
- [x] TP-20 safe preview card
- [x] TP-21 Preferences integration
- [x] TP-22 refresh themes action
- [x] TP-23 multi-theme import
- [x] TP-24 built-in theme assets
- [x] TP-25 user theme folder docs
- [x] TP-26 window chrome sync
- [x] TP-27 startup fallback
- [x] TP-28 50+ themes performance test
- [x] TP-29 end-to-end import test
- [x] TP-30 release QA docs
