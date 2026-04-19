# Теги и релизы

Кратко: как помечать версии в Git и что при этом делает CI.

## Зачем теги

- **Версия в Git** — неизменяемая метка на коммите (`v0.2.0` всегда указывает на один и тот же снимок кода).
- **Автосборка** — при пуше тега вида `v*` запускается workflow **Release** (см. `.github/workflows/release.yml`): сборки Linux и Windows, checksums, GitHub Release с текстом из [git-cliff](https://git-cliff.org/) и вложениями.

Теги **не заменяют** обычные коммиты в `main` / `dev`: сначала коммиты попадают в нужную ветку, затем на выбранный коммит вешается тег.

## Имя тега

- Используйте префикс **`v`** и семантическую версию, например: `v0.1.0`, `v1.2.3`.
- В CI и [cliff.toml](../cliff.toml) ожидаются теги, попадающие под шаблон **`v*`** (например `v0.1.0`). Теги вроде `1.0.0` без `v` workflow **не** подхватит.
- Предрелизные суффиксы в имени тега возможны, но в `cliff.toml` для changelog **пропускаются** паттерны вроде `beta`, `alpha`, `rc` в `skip_tags` — ориентируйтесь на обычные релизные теги `v1.0.0`.

## Создать и отправить тег

Убедитесь, что нужный коммит уже в удалённом репозитории (или запушьте ветку, затем тег).

**Тег на текущий коммит:**

```bash
git checkout main   # или dev — как принято у вас
git pull
git tag v0.2.0
git push origin v0.2.0
```

**Тег на конкретный коммит:**

```bash
git tag v0.2.0 abc1234
git push origin v0.2.0
```

**Удалить тег** (осторожно, если релиз уже опубликован):

```bash
git tag -d v0.2.0
git push origin :refs/tags/v0.2.0
```

На GitHub вручную: **Releases → Draft** не заменяет пуш тега; для автоматизации ориентируйтесь на `git push origin <tag>`.

## Что появится в GitHub после пуша тега

1. Запускается workflow **Release**.
2. Собираются артефакты **Windows** и **Linux** (zip).
3. Генерируется **`SHA256SUMS.txt`** для проверки архивов.
4. Формируется описание релиза и файл **`CHANGELOG-<тег>.md`** через **git-cliff** (группировка по Conventional Commits, при наличии токена — данные с GitHub API).
5. Создаётся или обновляется **GitHub Release** с телом из changelog и вложениями (zip + checksums + markdown).

Отдельно при пуше тега `v*` может выполняться **CI** из `.github/workflows/ci.yml` (тесты, анализ, при необходимости сборка Linux).

## Коммиты и changelog

Чтобы разделы релиза (Features, Bug Fixes и т.д.) выглядели аккуратно, сообщения коммитов лучше вести в стиле [Conventional Commits](https://www.conventionalcommits.org/), например:

- `feat(connections): …`
- `fix(postgres): …`
- `docs: …`

Остальные сообщения не пропадают: они попадают в группу **Other** (см. [cliff.toml](../cliff.toml)).

## Версия в приложении

Номер в **Git-теге** и поле **`version`** в [pubspec.yaml](../pubspec.yaml) — разные сущности. Для согласованности перед релизом обычно обновляют `pubspec.yaml`, коммитят, затем вешают тег на этот коммит (или наоборот — по договорённости в команде).

## Где смотреть настройки

| Файл | Назначение |
|------|------------|
| [.github/workflows/release.yml](../.github/workflows/release.yml) | Триггер по тегам `v*`, сборка, релиз |
| [.github/workflows/ci.yml](../.github/workflows/ci.yml) | CI при пуше веток и тегов `v*` |
| [cliff.toml](../cliff.toml) | Правила changelog (группы, теги, remote) |

## Локальная проверка changelog (опционально)

Установите [git-cliff](https://git-cliff.org/docs/installation), в корне репозитория:

```bash
git-cliff --latest --strip header
```

Для расширенного контекста (PR, контрибьюторы) нужен токен GitHub:

```bash
export GITHUB_TOKEN=ghp_...
export GITHUB_REPO=QueryaHub/Querya-Desktop
git-cliff --latest --github-token "$GITHUB_TOKEN" --github-repo "$GITHUB_REPO" --strip header
```

(В форке подставьте свой `owner/repo`.)
