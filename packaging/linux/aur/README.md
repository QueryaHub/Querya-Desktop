# Arch Linux (AUR)

Official **`querya-desktop`** package on AUR. Installs the Release portable Linux zip
under `/opt/querya-desktop`.

## Install

```bash
yay -S querya-desktop
# or: paru -S querya-desktop
```

## CI publish

| Trigger | Workflow |
|---------|----------|
| After GitHub Release | [Release](../../.github/workflows/release.yml) → job `publish-aur` |
| Manual hotfix | [Publish AUR](../../.github/workflows/aur-publish.yml) |

Requires repository secret **`AUR_SSH_PRIVATE_KEY`**. Without it, Release skips AUR
(no failed job). First `git push` creates the AUR repo automatically.

`pkgver` in the template PKGBUILD is synced on merge to `main` by
[version-bump.yml](../../.github/workflows/version-bump.yml); CI fills real
`sha256sums` and `.SRCINFO` at publish time via
[scripts/linux/aur_publish.sh](../../scripts/linux/aur_publish.sh).

## Local smoke test

```bash
cp packaging/linux/aur/{PKGBUILD,querya_desktop.desktop,querya_desktop.png} /tmp/querya-aur/
cd /tmp/querya-aur
makepkg -si
querya_desktop
```

## Updates

Prefer **`pacman -Syu`** / AUR helper updates over the in-app zip/AppImage
updater when running this package build.
