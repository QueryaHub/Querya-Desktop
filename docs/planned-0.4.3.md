# Planned release 0.4.3 — theme and extensions follow-ups

**Status:** **shipped in 0.4.3** (GitHub milestone [**0.4.3**](https://github.com/QueryaHub/Querya-Desktop/milestone/2), epic **#159** closed).  
**Depends on:** **0.4.2** custom theme registry (TP-01–TP-30, shipped).

This document captures work intentionally deferred from the first custom-theme pass.
See also [theme-parser-github-issues.md](theme-parser-github-issues.md) (TP-F1–TP-F4) and
[market-tech.md](market-tech.md) for the broader extensions marketplace direction.

## Theme folder and discovery

| ID | Issue | Scope | Summary |
|----|-------|--------|---------|
| **TP-F1** | [#160](https://github.com/QueryaHub/Querya-Desktop/issues/160) | `theme`, `filesystem` | **File watcher** for `{appSupport}/themes/` — auto-refresh the registry when files are added, removed, or renamed. Deferred: OS-specific watcher APIs and app lifecycle edge cases. |

## Theme distribution and metadata

| ID | Issue | Scope | Summary |
|----|-------|--------|---------|
| **TP-F2** | [#161](https://github.com/QueryaHub/Querya-Desktop/issues/161) | `theme`, `marketplace` | **Marketplace metadata** on `ThemeDefinition` / manifests — preview image, tags, homepage, license, author. Prerequisite for listing themes in a future Extensions UI. |
| **TP-F4** | [#163](https://github.com/QueryaHub/Querya-Desktop/issues/163) | `theme`, `network` | **Remote theme install** — download from URL with checksum/trust policy. Requires security review (HTTPS, signatures, user consent). |

## Authoring UX

| ID | Issue | Scope | Summary |
|----|-------|--------|---------|
| **TP-F3** | [#162](https://github.com/QueryaHub/Querya-Desktop/issues/162) | `theme`, `settings` | **Visual theme editor** in Preferences — tweak colors, export `querya.theme.v1`. Larger than parser/import; likely multiple PRs. |

## Extensions marketplace (optional overlap)

If **0.4.3** also starts the extensions shell from [market-tech.md](market-tech.md), align **TP-F2** theme metadata with `ExtensionManifest` so themes can appear as a category in **Explore**. Keep `lib/core/market/` isolated from theme parser internals.

## Suggested PR order (draft)

1. TP-F1 — watcher + debounced `loadAvailableThemes()`
2. TP-F2 — manifest fields + docs (no remote API yet)
3. TP-F3 — minimal editor MVP (export only) or split to **0.4.4**
4. TP-F4 — install-from-URL behind explicit user action

## Out of scope for 0.4.3

- Full marketplace backend and **Extensions** sidebar UI (may land in **0.5.0** per market-tech.md)
- P2 Mongo/Redis semantic token colors ([roadmap.md](roadmap.md))
- `re_editor` / LSP editor replacement
