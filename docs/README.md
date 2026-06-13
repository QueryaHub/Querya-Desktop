# Documentation

Index of Querya Desktop documentation, grouped by audience.

## For users

- [Getting started](getting-started.md) — prerequisites, install, first run.
- [User guide](user-guide.md) — connections, preferences, driver manager.
- [Security / local data](security.md) — where metadata and secrets are stored.

## For contributors

- [Contributing](../CONTRIBUTING.md) — workflow, CI, pre-PR checklist.
- [Architecture](architecture.md) — `lib/` layout and module responsibilities.
- [Theme system](theme.md) — runtime theming and VS Code theme tokens.
- [Theme import](theme-import.md) — supported `colors` keys and merge behavior.
- [Custom theme JSON](theme-custom-json.md) — `querya.theme.v1` schema and fallback rules.
- [Performance baseline](perf-baseline.md) — per-milestone DevTools checklist.

## For release managers

- [Tags and releases](tags-and-releases.md) — tag/release policy.
- [Release checklist](release-checklist.md) — step-by-step release flow.
- [macOS signing](macos-signing.md) — signing and notarization track.

## Planning

- [Roadmap](roadmap.md) — current direction and follow-ups.
- [Custom theme parser requirements](scheme-parcer.md) — JSON theme format and scaling spec.
- [Theme parser implementation plan](theme-parser-implementation-tasks.md) — task breakdown and architecture.
- [Theme parser GitHub issues](theme-parser-github-issues.md) — issue templates for epic #96–#125.
- [Marketplace extensions spec](market-tech.md) — extensions manager and marketplace integration.

## Archive

Historical design notes and one-off spikes, kept for context but no longer
maintained — see [`archive/`](archive/):

- [Repository audit (#91)](archive/AUDIT.md)
- [Editor package spike (#48)](archive/editor-spike-report.md)
- [`code_forge` + LSP evaluation (#52)](archive/code-forge-evaluation.md)
- [Theme research (RU)](archive/research_theme.md)
- [MySQL implementation plan](archive/mysql-implementation-plan.md)
