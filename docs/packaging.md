# Packaging: portable vs installable

Querya Desktop ships (and will ship) two download channels. See epic
[#379](https://github.com/QueryaHub/Querya-Desktop/issues/379).

| Channel | Typical artifact | Profile data |
|---------|------------------|--------------|
| **Portable** | `Querya-Desktop-{ver}-{os}.zip` (Flutter bundle) | OS app-support by default; optional sidecar — see below |
| **Installable** | AppImage, Windows setup, deb/rpm/Flatpak (planned) | Normal OS locations |

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

## Related code

- `lib/core/storage/app_data_root.dart` — detection and support-dir redirect
- Updater packaging context: `lib/core/updater/installers/update_install_context.dart`
- Release workflow: `.github/workflows/release.yml`
