# Теги и релизы

Кратко: как выставить версию и опубликовать бинарники через GitHub Actions.

## Рекомендуемый способ: тег → всё само

1. В [pubspec.yaml](../pubspec.yaml) выставьте **`version: X.Y.Z+N`** (semver до `+`, build number после).
2. Закоммитьте и запушьте в **`main`** (или в ветку, откуда мержите в `main`).
3. Создайте **аннотированный тег** с **той же semver-частью**, что в pubspec (без `+N`):
   - либо `0.1.1`, если в pubspec `0.1.1+1`;
   - либо `v0.1.1` — тоже допустимо, CI сравнивает с pubspec без префикса `v`.
4. Запушьте тег: `git push origin 0.1.1`

После этого workflow **[Release](../.github/workflows/release.yml)** запустится **автоматически**: соберёт **Windows**, **Linux** и **macOS** (zip), **`SHA256SUMS.txt`**, создаст или обновит **GitHub Release** с этими файлами.

Если после merge в `main` сработал **автобамп** версии в `pubspec`, а вы поставили тег со **старым** номером (например тег `0.1.1`, а в коммите уже `0.1.2+…`), сборка **всё равно пройдёт**: имена zip возьмутся из **pubspec** (`0.1.2`), а GitHub Release останется на **вашем теге** (`0.1.1`). В логах будет предупреждение; чтобы номер тега и архивов совпадали, ставьте тег на актуальный semver из `pubspec` (например `0.1.2`).

## Ручной запуск (как раньше)

- **Actions → Release → Run workflow** на нужном ref (обычно `main`).
- Workflow возьмёт semver из **pubspec** на этом коммите, соберёт zip и создаст **GitHub Release** с тегом **`X.Y.Z`** (как в pubspec до `+`), если тега ещё нет.

## Что внутри релиза

- Имена архивов: `Querya-Desktop-X.Y.Z-linux.zip`, `Querya-Desktop-X.Y.Z-windows.zip`, `Querya-Desktop-X.Y.Z-macos.zip` (внутри неподписанный `.app`).
- Версия для имён и тега — **semver из pubspec**; build `+N` попадает в текст релиза как **полный pubspec version**.

## Changelog (git-cliff)

- В репозитории есть [cliff.toml](../cliff.toml) — его можно использовать **локально** для черновика release notes:

  ```bash
  git-cliff --latest --strip header
  ```

- Генерация changelog **не подключена** к `release.yml`; при необходимости вставьте вывод git-cliff в описание релиза вручную на GitHub или расширьте workflow.

## Где смотреть настройки

| Файл | Назначение |
|------|------------|
| [.github/workflows/release.yml](../.github/workflows/release.yml) | Сборка + GitHub Release: **push тегов** `X.Y.Z` / `v*` или **ручной** запуск |
| [.github/workflows/ci.yml](../.github/workflows/ci.yml) | Тесты, analyze, smoke-сборка Linux при push тегов `X.Y.Z` или `v*` |
| [.github/workflows/version-bump.yml](../.github/workflows/version-bump.yml) | Автоподнятие patch/build при merge PR в `main` |
| [cliff.toml](../cliff.toml) | Правила changelog (локально) |

## Версия в приложении

Поле **`version`** в `pubspec.yaml` должно совпадать с ожидаемыми именами zip и тегом (semver до `+`).

## Платформы

- **Поставка через CI:** Windows, Linux и macOS (см. `release.yml`); macOS-сборка **без** подписи и notarize — для установки может понадобиться «Открыть» через контекстное меню при первом запуске.
