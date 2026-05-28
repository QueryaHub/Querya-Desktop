---
description: Querya Desktop GitFlow, branching, commits, and PR workflow
alwaysApply: true
---

# Querya Desktop — agent workflow

Desktop SQL/NoSQL client (PostgreSQL, MySQL, Redis, MongoDB).  
Стек: **Flutter** (Dart 3.5+), **shadcn_flutter** (vendored в `third_party/`), локальный SQLite + OS secure storage для секретов.

Remote: `git@github.com:QueryaHub/Querya-Desktop.git`

## Sync with remote (always)

Before checkout, branch, push, or PR — and **after** merge to `dev`:

```bash
git fetch --all --prune
git checkout dev
git pull --ff-only origin dev
```

Before push on a feature branch: `git fetch origin`, then rebase or merge remote.

**Full checks** before PR (локально, как в CI):

```bash
flutter pub get
flutter analyze
flutter test
```

Опционально перед релизом / крупным UI-PR:

```bash
flutter build linux --release   # или windows / macos
```

На Linux при `errno = 24` на analyze: `ulimit -n 8192` (см. [CONTRIBUTING.md](CONTRIBUTING.md)).

## Git branches

- **`main`**: production-ready; релизные теги (`X.Y.Z`) ставятся на коммиты, готовые к бинарникам.
- **`dev`**: интеграция; **все feature PR → `dev`**.
- **Feature**: `issue/<number>-<short-slug>` или `feat/<short-slug>` от актуального `dev`.

```bash
git fetch --all --prune && git checkout dev && git pull --ff-only origin dev
git checkout -b issue/38-querya-workbench-theme-models
# или: git checkout -b feat/postgres-sql-workspace-toolbar
```

Долгоживущие ветки по подсистемам (если согласовано с командой): `postgres-ench`, `mongo-ench`, `my_sql`, `design` — не создавать без необходимости; предпочитать короткие `issue/*` / `feat/*`.

**Hotfix** только по явному запросу: `hotfix/<short-slug>` от `main` → PR в `main`, затем back-merge в `dev`.

**Release**: версия в `pubspec.yaml`, тег на нужном коммите, workflow Release — см. [docs/tags-and-releases.md](docs/tags-and-releases.md), [docs/release-checklist.md](docs/release-checklist.md).

## Issue priority & roadmap

Живой roadmap: [docs/roadmap.md](docs/roadmap.md). Крупные темы (пример — epic **#37** theming): дочерние issues #38–#60.

| Область | Фокус |
|---------|--------|
| Connections | Tree, new connection, drivers, secure storage |
| PostgreSQL / MySQL | Browser, SQL workspace, grids, timeouts |
| Redis / MongoDB | Explorer, keys/collections, document editor |
| Theme / UI | `lib/core/theme/`, shadcn tokens, SQL editor (#37 epic) |
| CI / release | `.github/workflows/`, Linux deps, signing (macOS) |

Один issue → одна ветка → один PR. Scope = issue only — без drive-by рефакторинга.

## GitHub labels & milestones

### Milestone: **Theme system**

Epic [#37](https://github.com/QueryaHub/Querya-Desktop/issues/37) и дочерние issues **#38–#60** (кроме закрытого #56) — milestone [Theme system](https://github.com/QueryaHub/Querya-Desktop/milestone/1).

Новые theme-issues: label `theme` → workflow [issue-theme-milestone.yml](.github/workflows/issue-theme-milestone.yml) проставит milestone автоматически. Шаблон: [.github/ISSUE_TEMPLATE/theme_task.yml](.github/ISSUE_TEMPLATE/theme_task.yml).

### PR: labels + milestone (автоматика)

1. Ветка **`issue/<number>-<slug>`** (рекомендуется), например `issue/38-workbench-theme-models`.
2. В PR body: **`Closes #38`** (или Fixes/Resolves).
3. В title опционально: `feat(theme): … (#38)`.

Workflow [pr-linked-issue-metadata.yml](.github/workflows/pr-linked-issue-metadata.yml) копирует **все labels** и **milestone** с linked issue на PR при open/edit/sync.

Шаблон PR: [.github/pull_request_template.md](.github/pull_request_template.md).

### Ручное создание PR (если автоматика не сработала)

```bash
gh pr create --base dev \
  --milestone "Theme system" \
  --label "theme,enhancement" \
  --title "feat(theme): QueryaWorkbenchTheme models (#38)" \
  --body "$(cat <<'EOF'
## Summary
…

Closes #38
EOF
)"
```

Для editor-задач добавь label `editor`: `--label "theme,editor,enhancement"`.

### Issues

```bash
gh issue edit 38 --milestone "Theme system" --add-label "theme,enhancement"
```

Labels: `bug`, `enhancement`, `documentation`, `theme`, `editor`, `epic`.

После merge: issue `CLOSED`; `git fetch` + `git pull --ff-only` на `dev`.

## Commits and PRs

- [Conventional Commits](https://www.conventionalcommits.org/): `feat`, `fix`, `perf`, `docs`, `test`, `ci`, `chore`, `refactor` + scope.
- Scopes (примеры): `postgresql`, `mysql`, `mongodb`, `redis`, `connections`, `theme`, `editor`, `settings`, `ci`, `deps`, `ui`.
- Атомарные коммиты; не коммитить без явной просьбы пользователя.
- PR body: `Closes #N` когда применимо.
- **Не коммитить:** `.env`, ключи, `credentials.json`, экспортированные connection secrets.

Примеры:

```
feat(theme): add QueryaWorkbenchTheme and editor tokens
fix(postgresql): pass right-clicked table into Open in SQL
feat(mysql): SQL workspace statement timeout from settings
test(connections): panel layout with in-memory secrets
chore(release): bump version to 0.2.2+4
```

## Layout & checks

| Area | Path |
|------|------|
| Entry | `lib/main.dart`, `lib/app/app.dart` |
| Theme | `lib/core/theme/` |
| DB / pools | `lib/core/database/` |
| Storage / settings | `lib/core/storage/` |
| Features | `lib/features/<db\|area>/` |
| Shared UI | `lib/shared/widgets/` |
| Vendored UI | `third_party/shadcn_flutter/` (override в `pubspec.yaml`) |
| Tests | `test/` (mirror `lib/` where possible) |
| Docs | `docs/` |
| CI / release | `.github/workflows/` |

Зависимости: `pubspec.yaml`; lockfile **не** в git (см. `.gitignore`).

## Flutter conventions

- UI: **shadcn** `Theme.of(context).colorScheme`, не смешивать с Material без нужды (`material.` prefix где уже есть).
- Патчи shadcn — только в `third_party/shadcn_flutter`, с комментарием в `pubspec.yaml` `dependency_overrides`.
- Секреты: `flutter_secure_storage` / `connection_secrets_store` — без паролей в SQLite и логах ([docs/security.md](docs/security.md)).
- SQL editor: пока `TextField` / `QueryEditorTab`; подсветка — по issues #47–#50, не раздувать `TextField` ad hoc.
- Новый код: `flutter analyze` clean, тесты для нетривиальной логики (парсеры, storage, SQL helpers).

## Out of scope (unless issue says otherwise)

- Backend-сервисы, облачный sync аккаунтов.
- JDBC-драйверы (только встроенные Dart/native пути).
- Полная VS Code theme compatibility в одном PR (см. epic #37, поэтапно).
- Force-push на `main` / `dev` без явного запроса.
