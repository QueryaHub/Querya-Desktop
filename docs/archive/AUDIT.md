# Repository audit (#91)

Inventory of docs and tracked artifacts with a disposition decision. Goal: keep
the repository professional and easy to navigate without losing technically
valuable history.

Legend: **keep** = active, maintained · **archive** = historical, moved to
`docs/archive/` · **untrack** = remove from git, keep locally · **delete** = removed.

## Documentation

| Path | Disposition | Rationale |
|------|-------------|-----------|
| `README.md` | keep (rewritten) | Project front page — restructured with badges, features, quick start, docs index. |
| `CONTRIBUTING.md` | keep (expanded) | GitFlow, CI expectations, pre-PR checklist. |
| `CHANGELOG.md` | keep | Release history (Keep a Changelog). Links updated for moved files. |
| `docs/README.md` | new | Documentation index (User / Developer / Release / Theme / Archive). |
| `docs/getting-started.md` | new | Install + first run, extracted from README. |
| `docs/architecture.md` | new | `lib/` layout and module responsibilities for contributors. |
| `docs/user-guide.md` | keep | End-user guide. Kept current with the shipped UI. |
| `docs/security.md` | keep | Local-data and secrets model. |
| `docs/theme.md` | keep | Theme system reference (epic #37). |
| `docs/theme-import.md` | keep | VS Code theme import details. |
| `docs/roadmap.md` | keep (synced) | Living roadmap; synced with closed issues. |
| `docs/perf-baseline.md` | keep | Reusable per-milestone DevTools checklist. |
| `docs/tags-and-releases.md` | keep | Release/tag policy. |
| `docs/release-checklist.md` | keep | Release steps. |
| `docs/macos-signing.md` | keep | Signing/notarize track. |
| `docs/editor-spike-report.md` | archive | One-off editor package spike (#48); decision shipped in 0.4.0. |
| `docs/code-forge-evaluation.md` | archive | `code_forge`/LSP go/no-go spike (#52); NO-GO recorded. |
| `docs/research_theme.md` | archive | Background research (RU) behind the theme epic. |
| `docs/mysql-implementation-plan.md` | archive | Historical plan; MySQL is implemented (`lib/features/mysql/`). |

## Tracked artifacts

| Path | Disposition | Rationale |
|------|-------------|-----------|
| `.flutter-plugins-dependencies` | untrack | Generated per-machine; already in `.gitignore`. Caused recurring "local changes". |
| `.metadata` | keep | Standard Flutter project metadata. |
| `third_party/` | keep (untouched) | Vendored `shadcn_flutter`; retains its own license/docs. |
| `test/`, `.github/workflows/` | keep (untouched) | Behavior and CI unchanged by this cleanup. |

## Not in scope

- Rewriting `third_party/shadcn_flutter` documentation.
- Full RU+EN localization of docs (separate issue if needed).
- Marketing site / landing outside the repository.
