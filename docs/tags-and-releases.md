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

### Portable channel (сегодня)

Эти zip — **portable / relocatable bundles** (запуск из папки без установщика). Имена **не** меняем на `*-portable.zip`, чтобы не ломать in-app updater (`*-{linux,windows,macos}.zip`).

| Artifact | Contents |
|----------|----------|
| `Querya-Desktop-X.Y.Z-linux.zip` | Flutter linux `bundle/` (`querya_desktop`, `lib/`, `data/`) |
| `Querya-Desktop-X.Y.Z-windows.zip` | `querya_desktop.exe` + DLLs/data |
| `Querya-Desktop-X.Y.Z-macos.zip` | `querya_desktop.app` (signed/notarized when secrets are set) |
| `SHA256SUMS.txt` | Checksums of **all** files attached to the Release |

Версия в именах — **semver из pubspec**; build `+N` попадает в текст релиза как **полный pubspec version**.

Профиль по умолчанию всё равно в OS app-support; USB-style data → [packaging.md](packaging.md) (`QUERYA_PORTABLE` / `QueryaData/`).

### Installable channel

| Artifact | Notes |
|----------|--------|
| `Querya-Desktop-X.Y.Z-linux.AppImage` | [`scripts/linux/build_appimage.sh`](../scripts/linux/build_appimage.sh) (`chmod +x` then run) |
| `Querya-Desktop-X.Y.Z-windows-setup.exe` | Inno Setup (`packaging/windows/querya.iss`) |

deb / rpm / Flatpak: [#386](https://github.com/QueryaHub/Querya-Desktop/issues/386) / epic [#379](https://github.com/QueryaHub/Querya-Desktop/issues/379).

## Changelog в GitHub Release

При публикации релиза workflow **[Release](../.github/workflows/release.yml)** автоматически берёт секцию из [CHANGELOG.md](../CHANGELOG.md) для semver из `pubspec` (например `## [0.4.3]`). Скрипт: [scripts/extract-changelog-section.sh](../scripts/extract-changelog-section.sh).

Перед тегом убедитесь, что в `CHANGELOG.md` есть секция для этой версии — иначе job **Publish GitHub Release** упадёт.

Локальная проверка:

```bash
./scripts/extract-changelog-section.sh 0.4.3
```

### git-cliff (черновик)

Для черновика release notes из коммитов можно использовать [cliff.toml](../cliff.toml) локально:

```bash
git-cliff --latest --strip header
```

Генерация git-cliff **не подключена** к `release.yml`; источник правды для релизов — **CHANGELOG.md**.

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

- **Поставка через CI:** Windows, Linux и macOS (см. `release.yml`); macOS подписывается и notarize’ится, если настроены Apple secrets — иначе unsigned `.app` (может понадобиться «Открыть» через контекстное меню).
- Каналы загрузки и portable data: [packaging.md](packaging.md).
