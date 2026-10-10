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

### `QueryaActionButton`

Labelled outline button for toolbars (SQL editor: Execute, Explain, Cancel,
Begin / Commit / Rollback). Optional `icon`, `loading` (spinner instead of the
icon, button disabled), `isDestructive`, `tooltip`; `onPressed: null` disables it.

```dart
QueryaActionButton(
  label: 'Explain',
  icon: Icons.account_tree_outlined,
  onPressed: session.running ? null : () => explain(session),
)
```

Anti-pattern: a hand-built `OutlineButton` with its own spinner / icon coloring.

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

## Buttons and controls standard

The rules every button, icon button, menu trigger, dropdown trigger, search
field and tab strip follows. Epic #1331 migrates the app to them; the components
are `QueryaButton` (#1334) and `QueryaSplitButton` / `QueryaMenuButton` /
`QueryaDialogActions` (#1335), built on the metrics of #1333. Until a component
exists, new code uses the closest kit widget and the size from this table, never
a `shadcn_flutter` button.

### One control scale

Every control has one of three sizes. A row of controls uses **one** size, so
a toolbar has one height. Values are logical px at `uiScale` 1 and are scaled by
`context.scaled(...)` like the rest of the kit.

| Size | Height | Icon | Label | Horizontal padding | Icon-label gap | Use for |
|------|--------|------|-------|--------------------|----------------|---------|
| `sm` | 28 | 15 | 12 | 8 | 6 | tree headers, grid and panel toolbars, dense rows |
| `md` | 32 | 16 | 13 | 12 | 6 | top toolbars, editor toolbars, ERD, result bars |
| `lg` | 36 | 18 | 14 | 16 | 8 | dialog footers, forms, empty-state actions |

- The icon inside a button comes from its size. Hand-set icon sizes (13, 14,
  15, 16, 18) are not allowed; a button takes an `IconData`, not a sized `Icon`.
- Icon-only controls are square at the same height (`sm` 28 x 28, `md` 32 x 32,
  `lg` 36 x 36) and **always** carry a tooltip.
- A hit area is never smaller than the `sm` height. A 13 px glyph is drawn
  inside a 28 px target, not used as the target.
- Corner radius is one token (6), the same for buttons, icon buttons, dropdown
  triggers, search fields and tab pills. No 3 / 4 / 8 / 16 / 20 radii on controls.
- Dropdown triggers, search fields and tab strips share the heights above, so
  they line up with buttons in the same row.

### Variants

| Variant | Look | Use for |
|---------|------|---------|
| `primary` | filled with `workbench.accent`, text `onAccent` | the main action of a screen or dialog (one per surface) |
| `secondary` | transparent with a `borderSubtle` outline | ordinary actions: Refresh, Test connection, Export |
| `ghost` | no fill, no outline; hover tint | Cancel, Close, tertiary and toolbar actions |
| `destructive` | filled with `workbench.destructive` | irreversible actions: Delete, Drop, Disconnect |

A variant is a role, not a colour: do not pass colours. An active toggle (word
wrap, filter) uses `isActive` on an icon button, not a different variant.

### States

| State | Rule |
|-------|------|
| default | variant colours from `context.workbench` |
| hover | tint from the workbench, pointer cursor |
| pressed | one step darker than hover |
| focus | a 2 px `ring` outline **only for keyboard focus** (not after a mouse click) |
| disabled | 50 % opacity, `onPressed: null`, no hover, announced as disabled |
| loading | the icon (or a leading slot) becomes a `QueryaSpinner` of the same size, the button keeps its width and is not pressable; it is never a separate spinner next to the button |

All colours come from `context.workbench` / `context.semanticPalette`; all
durations from `QueryaMotion` (honouring Reduced / Off); all sizes from the
kit's tokens and `uiScale`. No colour, `Duration` or radius literals.

### Layout rules

- Gap between buttons in a row: 8 (`sm`: 6).
- A toolbar uses one size. Mixing `md` buttons with an `sm` menu trigger in one
  row is a bug.
- A split button ("Execute" with a dropdown) is one control: one height, one
  outline, one focus ring; the two parts are separated by a divider, not a gap.
- A menu trigger (`QueryaMenuButton`) is a button with a trailing chevron in
  the same size as its neighbours.
- Tooltips on icon-only controls use `kQueryaTooltipWait`; no literal delays.

### Dialog footers

Every dialog footer is a `QueryaDialogActions`, `lg`, right-aligned, 8 apart:

```
[ Cancel ]  [ Secondary ]  [ Primary or Destructive ]
```

- **Cancel / Close** is always `ghost`, placed first (left of the main action).
- Exactly **one** `primary` or `destructive` button per dialog, last (right).
  An irreversible main action is `destructive`, never `primary`.
- A secondary action in the footer (Test connection, Save as draft) is
  `secondary`.
- `Esc` triggers the cancel action and `Enter` the main action, in every
  dialog, through the footer.
- Inline form actions outside a footer (Test connection under the form) are
  `secondary lg` with the `loading` state of the button.

Canonical labels and roles from the review:

| Action | Variant |
|--------|---------|
| Cancel, Close, Dismiss, Not now | `ghost` |
| Create, Save, Apply, Connect, OK | `primary` |
| Retry | `secondary` (`primary` only when it is the single action of an error state) |
| Delete, Drop, Remove, Discard changes | `destructive` |
| Test connection, Browse… | `secondary` |

### Mapping from today's controls

| Today | Becomes |
|-------|---------|
| shadcn `PrimaryButton` | `QueryaButton` `primary` |
| shadcn `OutlineButton` | `QueryaButton` `secondary` |
| shadcn `GhostButton` | `QueryaButton` `ghost` |
| shadcn `DestructiveButton` | `QueryaButton` `destructive` |
| shadcn `SecondaryButton` | `QueryaButton` `secondary` |
| shadcn `normal` / `small` size | `lg` (dialogs, forms) / `sm` or `md` (toolbars, by row) |
| `QueryaActionButton` | `QueryaButton` `secondary`, `md` |
| `QueryaActionMenu` trigger | `QueryaMenuButton` |
| split "Execute" assembled by hand | `QueryaSplitButton` |
| shadcn / material `IconButton`, private `_TreeIconButton` | `QueryaIconButton` (with tooltip) |
| `InkWell` / `GestureDetector` around an icon or text | `QueryaButton` or `QueryaIconButton` |
| private `_ActionButton`, `_SmallActionButton`, `_ToolbarButton` | `QueryaButton` |
| show-password eye pasted in forms | one password field widget |

### Guards (landing with #1339)

| Test | Forbids |
|------|---------|
| `no_shadcn_buttons_test.dart` | `PrimaryButton`, `OutlineButton`, `GhostButton`, `DestructiveButton`, `SecondaryButton`, `LinkButton`, `ButtonSize`, `ButtonDensity` outside an allow-list |
| `no_raw_material_buttons_test.dart` | `IconButton`, `TextButton`, `ElevatedButton`, `OutlinedButton`, `FilledButton` |
| `no_ad_hoc_button_classes_test.dart` | a `*Button` class outside `lib/shared/widgets/`; a button-like `InkWell` / `GestureDetector` outside the kit |
| `button_literals_test.dart` | `waitDuration: Duration(...)` literals, `BorderRadius.circular(n)` on a kit control |

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
| `shared_does_not_import_shadcn_test.dart` | a new `package:shadcn_flutter` import in `lib/shared/` (ratchet: the allow-list only shrinks) | Flutter primitives and the kit tokens |

When adding a new shared component that replaces a Material one, add a guard
test in the same style and mention it here.
