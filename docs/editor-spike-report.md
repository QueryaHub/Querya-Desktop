# Editor package spike report (#48)

**Date:** 2026-05-28  
**Context:** Querya Desktop — Flutter desktop SQL/NoSQL client with `QueryaCodeEditor` (#47), `QueryaEditorTheme`, VS Code theme import (#43–#44).

## Goal

Choose an MVP highlighting/editor backend for **#49** (SQL) and **#50** (JSON), and a Phase 2 candidate if we outgrow MVP.

## Candidates evaluated

| Package | Pub | License | Maintainer signal |
|---------|-----|---------|-------------------|
| [syntax_highlight](https://pub.dev/packages/syntax_highlight) | ^0.5.0 | BSD-3 | Serverpod, active |
| [re_editor](https://pub.dev/packages/re_editor) + [re_highlight](https://pub.dev/packages/re_highlight) | ^0.8.0 | MIT | Reqable, active (2026) |
| [flutter_code_editor](https://pub.dev/packages/flutter_code_editor) | ^0.3.5 | Apache-2 / MIT | Akvelon, moderate |
| [code_forge](https://pub.dev/packages/code_forge) | ^9.9.0 | (see pub) | Active, large scope |

`flutter_syntax_highlighter` was excluded: display-only widget, not an editable editor.

## Scorecard (1–5, higher is better for Querya)

| Criterion | syntax_highlight | re_editor | flutter_code_editor | code_forge |
|-----------|------------------|-----------|---------------------|------------|
| VS Code theme fidelity | **5** — TextMate scopes + `HighlighterTheme` | 2 — highlight.js themes | 2 — highlight.dart themes | 3 — VS themes via re_highlight, not imported JSON |
| SQL quality | **4** — built-in `sql` grammar | **4** — sql in re_highlight | **4** — highlight languages | **4** |
| JSON quality | **4** — built-in `json` | **4** | **4** | **4** |
| 10k lines perf (editing) | 2 — highlighter only; editor = ours | **5** — custom layout, large text | 3 — CodeField on controller | **5** — rope, 100k+ claimed |
| Desktop focus / shortcuts | 3 — we own input | **5** — shortcuts, IME, folding | 4 | **5** |
| shadcn / Querya chrome fit | **5** — returns `TextSpan`, wraps in `QueryaCodeEditor` | 3 — own `CodeEditor` chrome | 3 — Material `CodeField` | 2 — full widget tree, heavy styling |
| License / maintenance | **5** / **4** | **5** / **4** | **4** / **3** | **3** / **3** (scope creep) |
| Integration cost vs #47 | **5** — incremental backend | 2 — replace widget | 3 — parallel stack | 1 — new controller + LSP surface |
| **Weighted total** | **~4.2** | **~3.5** | **~3.1** | **~3.0** |

## Test scenarios (planned manual matrix)

| # | Scenario | MVP expectation (syntax_highlight + TextField) | Phase 2 trigger |
|---|----------|--------------------------------------------------|-----------------|
| 1 | PG query ~200 lines | OK with debounced highlight in isolate | Jank >100ms keystroke |
| 2 | JSON document edit/save | OK; grammar + `QueryaEditorTheme` colors | Large single-line JSON |
| 3 | Paste 5000 lines | Risk: full re-highlight; **must** debounce + isolate | Switch to re_editor/code_forge |
| 4 | Theme switch during edit | OK — rebuild `HighlighterTheme` from `QueryaEditorTheme` / token map (#46) | — |

No automated perf numbers in this spike; recommend a **#58** benchmark before Phase 2.

## Architecture fit

Current stack:

```
QueryaApp → QueryaThemeScope → SqlEditorChrome → QueryaCodeEditor (TextField MVP)
ThemeController → QueryaEditorTheme (+ VS Code colors import)
```

### Option A — syntax_highlight behind QueryaCodeEditor (recommended MVP)

```
QueryaCodeEditor
  └─ TextFieldCodeEditorBackend (current)
  └─ HighlightingCodeEditorBackend (#49)
        └─ syntax_highlight.Highlighter → TextSpan overlay / custom EditableText layer
```

**Pros**

- Aligns with existing VS Code theme pipeline (`tokenColors` → #46, `colors` → workbench).
- SQL + JSON grammars included; extend via grammar JSON drop-in.
- Smallest diff from #47; workspaces stay decoupled from editor package.

**Cons**

- Not a full editor: line numbers, folding, multi-cursor → custom or later package.
- Large files need **isolate** highlight (#46 / performance issue).

### Option B — re_editor + theme adapter

Full editor widget; map `QueryaEditorTheme` → `CodeHighlightTheme` (highlight.js class names, **not** TextMate scopes).

**Pros:** Performance, folding, search, production-tested in Reqable.  
**Cons:** Imported VS Code `.json` themes do not apply 1:1; higher migration cost from `QueryaCodeEditor`.

### Option C — code_forge

IDE-grade (LSP, semantic tokens, AI). Uses `re_highlight` for syntax; **desktop-only** (`dart:io`), no web.

**Pros:** Future-proof for LSP/diagnostics.  
**Cons:** Heavy; theming ≠ Querya import path; large API surface; overkill for MVP SQL client.

### Option D — flutter_code_editor

Mature `CodeField`, but **highlight.js** themes — same VS Code fidelity problem as re_highlight.

## Recommendation

### MVP — **#49 / #50: `syntax_highlight`**

1. Add `HighlightingCodeEditorBackend` inside `QueryaCodeEditor`.
2. `await Highlighter.initialize(['sql', 'json'])`.
3. Build `HighlighterTheme` from `QueryaEditorTheme` (+ later `tokenColors` in #46).
4. Debounce highlight (50–100ms); run `highlight()` in **compute/isolate** for buffers >500 lines.
5. Keep `TextField` input path until highlight layer is stable.

### Phase 2 candidate — **`re_editor`**

Re-evaluate if:

- Users report lag on 5k+ line paste, or
- We need folding / block comments / bracket matching in-editor.

Plan: spike branch with `re_editor` only for `QueryEditorTab`, keep dialogs on MVP backend until theme adapter exists.

### Defer — **code_forge**

Track for a dedicated epic (LSP, diagnostics, multi-language). Not blocking Querya 0.3 theme milestone.

**Update (#52):** See [code-forge-evaluation.md](code-forge-evaluation.md) — **NO-GO** for 0.3.x; **re_editor** before `code_forge`; conditional LSP epic ~6–10 weeks if product triggers fire.

### Defer — **flutter_code_editor**

No advantage over syntax_highlight for VS Code theme fidelity.

## Proposed implementation slices

| Issue | Package | Scope |
|-------|---------|--------|
| **#49** | syntax_highlight | SQL in `QueryEditorTab`, PG/MySQL workspace |
| **#50** | syntax_highlight | JSON in `MongoDocumentEditor` |
| **#46** | syntax_highlight | `tokenColors` → `HighlighterTheme` bridge |
| **#58** | — | Benchmarks + widget tests for theme switch |
| Phase 2 | re_editor | Replace backend if benchmarks fail |

## Integration sketch (MVP)

```dart
// lib/core/editor/highlighting_code_editor_backend.dart (future #49)
final theme = HighlighterTheme.fromQueryaEditorTheme(context.editorTheme);
final highlighter = Highlighter(language: 'sql', theme: theme);

// On text change (debounced):
final span = await compute(
  (args) => args.highlighter.highlight(args.text),
  _HighlightArgs(highlighter, text),
);
// Apply span via RichText layer or package CodeEditor widget when upgrading
```

`HighlighterTheme.fromQueryaEditorTheme` maps `QueryaEditorTheme` token hues to TextMate scopes (keyword, string, comment, …) — detail in #46.

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Main-isolate jank on highlight | Isolate + debounce; cap sync highlight at N lines |
| VS Code theme only sets `colors`, not `tokenColors` | Fall back to `QueryaEditorTheme` defaults (#38) |
| shadcn TextField vs highlight repaint | Start with highlight-on-idle; consider `syntax_highlight` `CodeEditor` widget in #49 PR if needed |
| Duplicate editor stacks | Single entry: `QueryaCodeEditor` only |

## Decision

| Phase | Choice |
|-------|--------|
| **MVP (#49, #50)** | **syntax_highlight** behind `QueryaCodeEditor` |
| **Phase 2** | **re_editor** if perf/feature gap |
| **Not now** | code_forge, flutter_code_editor as primary |

## References

- [syntax_highlight](https://pub.dev/packages/syntax_highlight) — TextMate, SQL/JSON grammars
- [re_editor](https://pub.dev/packages/re_editor) — Reqable editor widget
- [code_forge](https://pub.dev/packages/code_forge) — LSP + rope editor
- [flutter_code_editor](https://pub.dev/packages/flutter_code_editor) — CodeField + highlight
- Querya: `docs/theme-import.md`, `lib/core/editor/querya_code_editor.dart`
