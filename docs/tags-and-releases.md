# Теги и релизы

Кратко: как выставить версию и опубликовать бинарники через GitHub Actions.

## Как устроен релиз сейчас

- Workflow **[Release](../.github/workflows/release.yml)** запускается **вручную** (**Actions → Release → Run workflow**), а не автоматически при пуше тега.
- Версия для артефактов и имени тега берётся из поля **`version`** в [pubspec.yaml](../pubspec.yaml) (например `0.9.0+42` → тег `v0.9.0`, build number в метаданных релиза).
- Собираются артефакты **Windows** и **Linux** (zip), публикуется **`SHA256SUMS.txt`**, создаётся **GitHub Release** с фиксированным телом (описание из workflow, не git-cliff в CI).

## Changelog (git-cliff)

- В репозитории есть [cliff.toml](../cliff.toml) — его можно использовать **локально** для черновика release notes:

  ```bash
  git-cliff --latest --strip header
  ```

- Генерация changelog **не подключена** к `release.yml`; при необходимости вставьте вывод git-cliff в описание релиза вручную на GitHub или расширьте workflow.

## Имя тега

- Workflow создаёт тег вида **`v` + semver из pubspec** (например `v0.9.0`).
- Чтобы не путаться с другими схемами, придерживайтесь **`v*`** для релизных тегов.

## Перед запуском Release

1. Обновите `version` в `pubspec.yaml`, закоммитьте в ветку по вашему процессу.
2. Убедитесь, что **CI** (тесты + analyze) зелёные на этом коммите.
3. Запустите workflow **Release** на нужном коммите (обычно `main`).

## Локальная проверка changelog (опционально)

```bash
git-cliff --latest --strip header
```

С токеном GitHub (PR, авторы) см. историческую секцию в предыдущих версиях этого файла или документацию git-cliff.

## Где смотреть настройки

| Файл | Назначение |
|------|------------|
| [.github/workflows/release.yml](../.github/workflows/release.yml) | Ручной релиз, сборка, GitHub Release |
| [.github/workflows/ci.yml](../.github/workflows/ci.yml) | Тесты, analyze, smoke-сборка Linux при push тегов `X.Y.Z` или `v*` |
| [.github/workflows/version-bump.yml](../.github/workflows/version-bump.yml) | Автоподнятие patch/build при merge в `main` |
| [cliff.toml](../cliff.toml) | Правила changelog (локально) |

## Версия в приложении

Поле **`version`** в `pubspec.yaml` должно соответствовать тому, что вы ожидаете увидеть в имени zip и в GitHub Release. Тег создаётся workflow’ом из этой версии.

## Платформы

- **Поставка через CI:** Windows и Linux (см. `release.yml`).
- **macOS:** локальная сборка возможна (`flutter build macos`); отдельного job подписи/notarize в этом workflow нет.
