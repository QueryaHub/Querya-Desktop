# Packaging: portable vs installable

Querya Desktop ships (and will ship) two download channels. See epic
[#379](https://github.com/QueryaHub/Querya-Desktop/issues/379).

| Channel | Typical artifact | Profile data |
|---------|------------------|--------------|
| **Portable** | `Querya-Desktop-{ver}-{os}.zip` (Flutter bundle) | OS app-support by default; optional sidecar — see below |
| **Installable** | AppImage, Windows setup, `.deb`, `.rpm`, Flatpak | Normal OS locations |

## Portable profile (`QueryaData`)

By default the zip is a **relocatable binary** only: settings DB, themes, and
extensions still use OS paths (`getApplicationSupportDirectory`,
`~/.querya/extensions`, …).

To keep profile data next to the app (USB-style):

1. Set environment variable **`QUERYA_PORTABLE=1`** (also `true` / `yes` / `on`),
   **or**
2. Create a folder named **`QueryaData`** next to `querya_desktop` /
   `querya_desktop.exe` / the `.AppImage` file.

Then local data is stored under that folder:

| Kind | Path under `QueryaData/` |
|------|--------------------------|
| SQLite DB | `querya_desktop/querya.db` |
| Themes | `themes/` |
| Extensions | `extensions/` |
| Sandbox / audit logs | `logs/` |

On Linux AppImage, the install directory is the parent of `$APPIMAGE`.

### Secrets

Connection passwords remain in the **OS keyring** (`flutter_secure_storage` /
libsecret / Credential Manager / Keychain). Portable mode does **not** move
secrets into `QueryaData` in v1.

## Bundle / application IDs

| Platform | ID |
|----------|----|
| Linux (`APPLICATION_ID`) | `com.queryahub.querya_desktop` |
| macOS (bundle id) | `com.queryahub.queryaDesktop` |
| Windows (Company / Product) | `QueryaHub` / `Querya Desktop` |

Legacy `com.example.*` support directories are migrated once into the new paths
(see `AppDataRoot.migrateLegacySupportIfNeeded`).

## Related code

- `lib/core/storage/app_data_root.dart` — portable detection, support-dir redirect, id migration
- Updater packaging context: `lib/core/updater/installers/update_install_context.dart`
- Release workflow: `.github/workflows/release.yml`

## Linux distro packages

All installable Linux formats reuse the same Flutter `build/linux/x64/release/bundle`
payload as the portable zip and AppImage.

| Format | Build script | Install |
|--------|--------------|---------|
| `.deb` | [`scripts/linux/build_deb.sh`](../scripts/linux/build_deb.sh) | `sudo apt install ./Querya-Desktop-{ver}-linux.deb` |
| `.rpm` | [`scripts/linux/build_rpm.sh`](../scripts/linux/build_rpm.sh) | `sudo dnf install ./Querya-Desktop-{ver}-linux.rpm` |
| Flatpak | [`scripts/linux/build_flatpak.sh`](../scripts/linux/build_flatpak.sh) | `flatpak install --user ./Querya-Desktop-{ver}-linux.flatpak` |
| AUR | [`packaging/linux/aur/`](../packaging/linux/aur/) | `yay -S querya-desktop` (CI publishes on Release when `AUR_SSH_PRIVATE_KEY` is set) |

**Runtime dependencies (deb/rpm):** GTK 3, libsecret, GLib; app indicator recommended for tray.

### Updater policy

| Install type | In-app updater |
|--------------|----------------|
| Portable zip / AppImage | Downloads matching release asset (zip or AppImage) |
| `.deb` / `.rpm` | Use **apt** / **dnf** (or distro equivalent); in-app install is not offered |
| Flatpak | Use **`flatpak update`** (`FLATPAK_ID` / managed runtime — see `update_install_context.dart`) |
| Snap | Use **`snap refresh`** when/if a Snap build ships |

### Flatpak sandbox notes

The bundled Flatpak grants network, home, and D-Bus access to the freedesktop
secrets service (libsecret). Some database setups (Unix sockets outside `$HOME`,
custom TLS stores) may need extra permissions, e.g.:

```bash
flatpak override --user com.queryahub.querya_desktop --filesystem=/var/run/postgresql:ro
```

Flathub submission can reuse [`packaging/linux/flatpak/com.queryahub.querya_desktop.yml`](../packaging/linux/flatpak/com.queryahub.querya_desktop.yml).
