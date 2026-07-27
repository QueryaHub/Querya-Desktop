# Arch Linux (AUR)

Community packaging for Arch-based distros. The PKGBUILD installs the official
**portable Linux zip** from GitHub Releases under `/opt/querya-desktop`.

## Before publishing to AUR

1. Copy `PKGBUILD`, `querya_desktop.desktop`, and `querya_desktop.png` into a clean build directory.
2. Bump `pkgver` / `pkgrel` to match the GitHub Release tag and AUR revision.
3. Run `makepkg -si` locally and smoke-launch `querya_desktop`.
4. Generate `.SRCINFO`: `makepkg --printsrcinfo > .SRCINFO`
5. Push to your AUR repo (e.g. `querya-desktop`).

`querya_desktop.desktop` and the 512×512 icon are the same assets used by
`.deb` / `.rpm` packaging (`packaging/linux/querya_desktop.desktop` and
`macos/Runner/Assets.xcassets/.../app_icon_512.png`).

## Updates

Prefer **`pacman -Syu`** / AUR helper updates over the in-app zip/AppImage
updater when running this package build.
