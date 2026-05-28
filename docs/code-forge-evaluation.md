# code_forge & LSP evaluation (#52)

**Date:** 2026-05-28  
**Status:** Spike complete — **NO-GO** as primary editor for Querya 0.3.x  
**Conditional:** separate **Editor LSP** epic only if product triggers below are met  
**Prerequisite docs:** [editor-spike-report.md](editor-spike-report.md) (#48), theme milestone (#37–#57)

## Executive summary

| Question | Answer |
|----------|--------|
| Replace `syntax_highlight` + `QueryaCodeEditor` now? | **No** — MVP stack meets theme milestone goals |
| Adopt `code_forge` before `re_editor`? | **No** — higher cost, weaker VS Code theme fidelity |
| Start an LSP epic via `code_forge`? | **Only if** inline diagnostics / semantic tokens / 10k+ line editing become P0 |
| Recommended next editor step | **`re_editor` spike** when benchmarks fail (see #58 / paste scenarios) |

**Decision:** **NO-GO** for integrating `code_forge` in the current release line. Document a deferred epic breakdown for a future “professional SQL IDE” phase.

---

## Context (post–theme milestone)

Querya Desktop today:

```
ThemeController → QueryaThemeScope
SqlEditorChrome → QueryaCodeEditor
  ├─ TextField (shadcn/material)
  └─ QueryaHighlightController + syntax_highlight (SQL/JSON)
       ├─ HighlighterTheme from QueryaEditorTheme + tokenColors (#46)
       └─ isolate highlight for buffers ≥ 8 KB
```

Delivered: #47 abstraction, #49/#50 highlighting, #46 tokenColors, #58 tests, theme docs.

`code_forge` (^10.x) is a **full editor widget** with a **Rust FFI backend** (rope, folding, LSP client, optional AI completion). It is not a highlighter-only layer.

---

## Spike questions (from #52)

### 1. Does it fit `QueryaCodeEditor` (#47)?

**Partially — not as a drop-in backend.**

| Aspect | `syntax_highlight` (current) | `code_forge` |
|--------|------------------------------|--------------|
| Integration | `QueryaHighlightController` extends `TextEditingController`; same chrome (`SqlEditorChrome`) | `CodeForge` + `CodeForgeController`; own `RenderBox`, gutter, popups |
| External controller | Works with workspace-owned `TextEditingController` | `CodeForgeController` — sync layer needed |
| Widget tree | Stays inside shadcn `TextField` | Parallel editor subtree; risk of double chrome |

**Verdict:** A new backend would **replace** the editor body, not extend `HighlightingCodeEditorBackend` from #48. Estimate **2–3 weeks** for adapter + theme bridge + workspace wiring, not a small PR.

### 2. Gutter / line numbers vs `QueryaEditorTheme`

`code_forge` themes target **re_highlight** class names (`atomOneDarkTheme`, etc.), not TextMate scopes or imported VS Code JSON.

| Token source | Maps cleanly to Querya import? |
|--------------|-------------------------------|
| `QueryaEditorTheme` flat fields | Manual map → `EditorTheme` / gutter config |
| VS Code `tokenColors` | **No** 1:1 — same gap as `re_editor` |
| VS Code `colors` (workbench) | N/A for editor chrome inside CodeForge |

**Verdict:** Acceptable for a **fixed Querya palette**, poor for **user-imported VS Code themes** unless we build a second adapter (high effort).

### 3. SQL LSP — available vs lex-only highlight

| Engine | Role | Fit for Querya |
|--------|------|----------------|
| `syntax_highlight` | TextMate lex highlight | **Current** — no server, works offline |
| [Postgres Language Server](https://pg-language-server.com/) | LSP: complete, diagnostics, lint | **PG workspaces** — external binary (`postgres-language-server` / `@postgrestools/postgrestools`) |
| MySQL | No mainstream SQL LSP with MySQL parser parity | Lex-only or custom later |
| Mongo (JSON) | `json` LSP exists; not SQL | Keep JSON grammar in editor |

`code_forge` provides an **LSP client** (stdio / WebSocket); Querya would still own **process management** (spawn per connection, env, cwd, shutdown, stderr logs).

**Verdict:** LSP is **orthogonal** to choosing `code_forge`. We could run PLS with a lighter editor (`re_editor`) + `flutter_lsp` / custom client later. **Do not adopt code_forge solely for LSP.**

### 4. Bundle size and native dependencies

| Dependency | Impact |
|------------|--------|
| `await RustLib.init()` in `main()` | Required; FFI to Rust rope/sum-tree |
| Rust toolchain | **All devs + CI** need `rustup`; release builds use AOT (debug noted 60% slower on large files) |
| Platform artifacts | Per-target native libs in Flutter build |
| External LSP binaries | Additional download/bundle (PG LS ~tens of MB per platform) |

Querya already ships **FFI** (`sqflite_common_ffi`, DB drivers). Adding **editor Rust** + **LSP servers** is a step-change in release engineering.

**Verdict:** Acceptable for a dedicated IDE phase; **too heavy** for theme/editor MVP closure.

### 5. AI completion in the package — do we need it?

`code_forge` advertises multi-model AI completion. Querya is a **database client**, not an AI IDE.

**Verdict:** **Out of scope** — disable in config; do not factor into buy decision.

---

## Comparison matrix (2026-05)

Scores 1–5 (higher = better for Querya today).

| Criterion | syntax_highlight (now) | re_editor | code_forge |
|-----------|------------------------|-----------|------------|
| VS Code import fidelity | **5** | 2 | 2 |
| SQL + JSON editing | **4** | **4** | **4** |
| 10k+ lines | 3 (isolate) | **5** | **5** |
| shadcn / SqlEditorChrome fit | **5** | 3 | 2 |
| Integration cost | **5** | 3 | 1 |
| LSP / diagnostics | 1 | 1 | **5** |
| Build / ops complexity | **5** | **4** | 2 |

**Weighted for Querya 0.3:** keep **syntax_highlight**; plan **re_editor** before **code_forge**.

---

## Triggers to reopen (go/no-go gates)

Re-evaluate `code_forge` or a full LSP stack when **all** are true:

1. **Perf:** p95 keystroke-to-paint > 100 ms on 5k-line SQL with isolate + debounce (#58 benchmark).
2. **Product:** inline SQL diagnostics or semantic tokens are **P0** on the roadmap.
3. **Engineering:** team commits to Rust in CI + bundling PG Language Server (or equivalent) per OS.

If only (1) is true → spike **re_editor** first (lower risk).

---

## Recommendation

### NO-GO (now)

- Do **not** add `code_forge` to `pubspec.yaml` for 0.3.x.
- Do **not** block theme epic closure on LSP.

### YES (keep)

- `syntax_highlight` + `QueryaCodeEditor` + `tokenColors` bridge.
- Isolate threshold `kSyntaxHighlightIsolateThreshold = 8192`.
- Optional **re_editor** benchmark branch when users report large-script lag.

### CONDITIONAL epic (later)

If triggers above fire, prefer epic **“Editor platform (LSP)”** rather than a theme sub-task:

| Slice | Scope | Estimate |
|-------|--------|----------|
| E1 | Editor backend decision (`re_editor` vs `code_forge`) from benchmark | 3–5 d |
| E2 | `QueryaEditorTheme` → editor package theme adapter | 5–8 d |
| E3 | `LspProcessManager` (stdio spawn, lifecycle, logging) | 5–8 d |
| E4 | Postgres: PLS config UI + connection-scoped server | 8–13 d |
| E5 | Diagnostics gutter + quick fixes in SQL tabs | 8–13 d |
| E6 | MySQL/Mongo: lex-only or separate spikes | TBD |
| E7 | Packaging: CI Rust + LSP binaries for Linux/macOS/Windows | 5–8 d |

**Only if E1 selects `code_forge`:** add E0 `RustLib.init()`, FFI crash telemetry, profile-only perf tests.

Total rough order: **~6–10 weeks** engineering (not 3–5 day spike).

---

## Manual smoke (not run in CI)

Spike did **not** add `code_forge` to the repo (avoids Rust CI). If revisiting:

1. `flutter create` sample + `code_forge: ^10.0.1` + `RustLib.init()`.
2. Load 50k-line SQL paste — measure frame time profile vs release.
3. Map `QueryaEditorTheme.darkDefault` colors to `editorTheme` — screenshot diff vs VS Code import.
4. Spawn `postgres-language-server lsp-proxy` — verify completions on `SELECT `.
5. Toggle theme during edit — check gutter/selection colors.

Record results in a comment on #52 when executed.

---

## References

- [code_forge on pub.dev](https://pub.dev/packages/code_forge) — Rust backend, LSP, no Flutter web
- [editor-spike-report.md](editor-spike-report.md) — MVP choice `syntax_highlight`
- [Postgres Language Server](https://github.com/supabase-community/postgres-language-server)
- Querya: `lib/core/editor/querya_code_editor.dart`, `syntax_highlight_isolate.dart`

## Decision log

| Date | Decision |
|------|----------|
| 2026-05-28 | **NO-GO** primary adoption; defer LSP epic; **re_editor** before `code_forge` |
