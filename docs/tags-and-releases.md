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

## Beta-канал (pre-release)

Beta — это GitHub **pre-release** с версией вида `X.Y.Z-beta.N`. Пользователи **Stable** его не видят: приложение читает `releases/latest`, а бета никогда не становится `latest`. Пользователи, выбравшие **Beta / Early Access** (Настройки → Release channel), получают самую высокую версию из всех релизов; бета заменяется финальным релизом той же версии (`0.5.0-beta.2` < `0.5.0`). Пакетные установки (AUR, `.deb`, `.rpm`, Snap, Flatpak) получают только stable от своего менеджера пакетов.

### Как выпустить бету

1. Ветка `release/X.Y.Z` от `dev`.
2. `scripts/release/prepare_beta.sh X.Y.Z N`: ставит `version: X.Y.Z-beta.N+B` в `pubspec.yaml` и секцию `## [X.Y.Z-beta.N] - <дата>` в `CHANGELOG.md` (под `## [Unreleased]`, её содержимое становится заметками беты). Ничего не коммитит.
3. `scripts/release/check_release.sh X.Y.Z-beta.N` — проверка до тега (версия в pubspec = тег, есть секция CHANGELOG, у беты есть build number, тег свободен) и описание того, что сделает workflow.
4. Коммит, **аннотированный** тег `X.Y.Z-beta.N` на этом коммите, `git push origin HEAD X.Y.Z-beta.N`.
5. Workflow **Release** собирает всё и публикует **pre-release** (не `latest`), пропускает AUR и репозитории APT/DNF. В описание релиза добавляется пометка о бете. PR из `release/*` проходит job **Release branch check** (`check_release.sh`).

Исправления беты: `beta.2`, `beta.3` из той же ветки тем же способом. Заметки CHANGELOG беты — дельта; финальный релиз повторяет всё.

### Как повысить бету до stable (promote)

Когда бета пролежала несколько дней без блокеров: в `pubspec.yaml` `version: X.Y.Z+B`, секция `## [X.Y.Z]` с **полными** заметками, `check_release.sh X.Y.Z`, аннотированный тег `X.Y.Z` (теги бет остаются). Это обычный релиз: он `latest`, уходит в AUR и APT/DNF, и пользователи Beta и Stable получают его. Пакеты беты (`X.Y.Z~beta.N`) обновляются до финального пакета.

### Как откатить плохой релиз

Пометьте плохой **stable** как pre-release (или удалите): `releases/latest` снова вернёт предыдущий. AUR и APT/DNF откатываются отдельно (удалить пакет из репозитория `QueryaHub/repo` / вернуть предыдущий `pkgver`).

### Ловушки

| Симптом | Причина | Что делать |
|---|---|---|
| Job **Publish GitHub Release** падает | нет секции `## [X.Y.Z-beta.N]` в `CHANGELOG.md` | `check_release.sh` называет её; добавьте до тега |
| После merge в `main` версия беты стала `0.5.1+…` | раньше `version-bump.yml` отрезал `-beta.N` | теперь бета-версия не трогается (notice в логе); тег всё равно ставьте вручную на коммит ветки `release/*` |
| Предупреждение `Git tag is … but pubspec semver is …` | тег и pubspec не совпадают | `check_release.sh` до тега; артефакты называются по pubspec |
| Бета предложена Stable-пользователям | release опубликован без `prerelease` | не должно случаться (#1492); проверьте, что в версии/теге есть `-` |
| Пакет беты «новее» финального | версия `0.5.0-beta.1` в dpkg/rpm | пакеты получают `0.5.0~beta.1` (#1494) |

### Что получает каждый канал

| | Stable (GitHub `latest`) | Beta / Early Access | AUR, APT/DNF, Flatpak |
|---|---|---|---|
| `X.Y.Z-beta.N` | нет | да | нет (бета только на GitHub, решение #1495) |
| `X.Y.Z` | да | да | да |

## Ручной запуск (как раньше)

- **Actions → Release → Run workflow** на нужном ref (обычно `main`).
- Workflow возьмёт semver из **pubspec** на этом коммите, соберёт zip и создаст **GitHub Release** с тегом **`X.Y.Z`** (как в pubspec до `+`), если тега ещё нет. Если в pubspec версия с `-` (бета), релиз будет pre-release.

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
| `Querya-Desktop-X.Y.Z-linux.deb` | Debian/Ubuntu — [`scripts/linux/build_deb.sh`](../scripts/linux/build_deb.sh) |
| `Querya-Desktop-X.Y.Z-linux.rpm` | Fedora/RHEL — [`scripts/linux/build_rpm.sh`](../scripts/linux/build_rpm.sh) |
| `Querya-Desktop-X.Y.Z-linux.flatpak` | Distro-agnostic — [`scripts/linux/build_flatpak.sh`](../scripts/linux/build_flatpak.sh) |
| `Querya-Desktop-X.Y.Z-windows-setup.exe` | Inno Setup (`packaging/windows/querya.iss`) |

```bash
sudo apt install ./Querya-Desktop-X.Y.Z-linux.deb
sudo dnf install ./Querya-Desktop-X.Y.Z-linux.rpm
flatpak install --user ./Querya-Desktop-X.Y.Z-linux.flatpak
```

**Arch (AUR):** `yay -S querya-desktop` — auto-published by Release CI when `AUR_SSH_PRIVATE_KEY` is configured ([`packaging/linux/aur/`](../packaging/linux/aur/)).

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
