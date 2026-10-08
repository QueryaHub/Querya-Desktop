# Querya UI Kit

Shared widgets live in `lib/shared/widgets/` and are exported by
`package:querya_desktop/shared/widgets/widgets.dart`. Use them instead of raw
Material / ad-hoc widgets so every screen follows the active theme, motion
settings and VS Code-imported tokens.

## Components

### `QueryaConfirmDialog` (and `QueryaModalDialog`)

Confirmations and modal forms. Never use Material `AlertDialog`.

```dart
final ok = await QueryaConfirmDialog.show(
  context: context,
  title: 'Delete connection?',
  message: 'This cannot be undone.',
  confirmLabel: 'Delete',
  isDestructive: true,
);
if (ok == true) { /* … */ }
```

Anti-pattern: `showDialog(builder: (_) => AlertDialog(...))`.

### `QueryaSearchField`

Debounced search input (`debounceDuration`, default 250 ms) with optional
`shortcutHint`.

```dart
QueryaSearchField(
  placeholder: 'Filter tables…',
  onChanged: (q) => setState(() => _query = q),
)
```

Anti-pattern: a bare `TextField` with a manual `Timer` for debouncing.

### `QueryaIconButton` / `QueryaToolbarButton`

Compact toolbar buttons with `tooltip`, `isActive`, `isDestructive` and a
`QueryaIconButtonDensity`.

```dart
QueryaIconButton(
  icon: Icons.refresh,
  tooltip: 'Refresh',
  onPressed: _reload,
)
```

Anti-pattern: `IconButton` without a tooltip, hard-coded `Color(0xFF…)` icons.

### `QueryaSpinner`

Progress indicator with `QueryaSpinnerSize.sm | md | lg` and an optional
`label`. It takes its color from the workbench accent.

```dart
const QueryaSpinner(size: QueryaSpinnerSize.sm, label: 'Loading…')
```

Anti-pattern: `CircularProgressIndicator()` directly (guarded, see below).

### `QueryaBadge`

Semantic badges for constraints, types and states: `QueryaBadge.primaryKey()`,
`.foreignKey()`, `.dataType('uuid')`, `.status('Online', status: QueryaBadgeStatus.success)`,
`.readOnly()`, or `QueryaBadge(label: …)` with explicit colors.

Anti-pattern: a `Container` with a fixed background and text per call site.

### `QueryaEmptyState`

Placeholder for empty lists, search results and tabs: `title`, optional
`description`, `icon`, and an action (`actionLabel` + `onAction`, or a custom
`action`). Use `compact: true` inside small panes.

```dart
QueryaEmptyState(
  title: 'No tables found',
  description: 'Create a table or change the filter.',
  actionLabel: 'Refresh',
  onAction: _reload,
)
```

### Other shared widgets

`QueryaDropdown` (never Material `DropdownButton` / `PopupMenuButton`),
`QueryaActionMenu`, `QueryaTabStrip`, `showAppToast`, `showAppDialog`.

## Design tokens

Read colors from the theme scope, never from literals.

| Token | Access | Use for |
|-------|--------|---------|
| `canvas`, `surface`, `sidebarBackground`, `editorBackground` | `context.workbench` | page, card, sidebar and editor backgrounds |
| `borderSubtle` | `context.workbench` | dividers and outlines |
| `accent`, `onAccent` | `context.workbench` | primary actions, selection, spinner |
| `mutedForeground` | `context.workbench` | secondary text, placeholders |
| `destructive`, `success`, `warning` | `context.workbench` | state feedback |
| `gitModified`, `gitUntracked` | `context.workbench` | change decorations |
| `action`, `success`, `destructive`, `muted` | `context.semanticPalette` | meaning-based roles |
| `type1`…`type5` | `context.semanticPalette` | stable distinct colors for charts and type badges |

```dart
final wb = context.workbench;
final palette = context.semanticPalette;
Container(color: wb.surface, child: Text('x', style: TextStyle(color: wb.mutedForeground)));
```

## Extensions and custom themes

Extension UI (SDUI) and third-party drivers should rely on the same roles so a
VS Code theme imported via [theme-import.md](theme-import.md) recolors them
too: describe intent (primary action, destructive, muted), not colors. Missing
workbench keys fall back as described in [theme.md](theme.md).

## Guard tests

`test/guards/` keeps legacy widgets from coming back; each scans `lib/`:

| Test | Forbids | Use instead |
|------|---------|-------------|
| `no_raw_material_dialogs_test.dart` | `AlertDialog` | `QueryaModalDialog`, `QueryaConfirmDialog` |
| `no_material_dropdowns_test.dart` | `DropdownButton(FormField)`, `PopupMenuButton`, `showMenu` | `QueryaDropdown`, `QueryaActionMenu` |
| `no_raw_progress_indicators_test.dart` | `CircularProgressIndicator` outside `QueryaSpinner` | `QueryaSpinner` |

When adding a new shared component that replaces a Material one, add a guard
test in the same style and mention it here.
