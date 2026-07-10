# macOS code signing and notarization

CI now builds a **macOS zip** with an **unsigned** `.app` by default. When Apple Developer secrets are configured in the repository, the same workflow will also **code-sign, notarize, and staple** the app, so users can open it with a double-click instead of using **right-click → Open**.

> This is a one-time setup. After the secrets are in place, every future tag release (`0.4.10`, `0.4.11`, …) will produce a signed macOS build automatically.

---

## What the user sees

| State | Gatekeeper behavior |
|-------|---------------------|
| Unsigned / not notarized | Scary dialog, user must right-click → Open, sometimes go to **System Settings → Privacy & Security** |
| Signed + notarized + stapled | Double-click opens normally, no warnings |

---

## Prerequisites

1. **Apple Developer Program** membership — **$99/year** (required for a Developer ID certificate).
2. A **Mac** (or Xcode Cloud) to create the Certificate Signing Request and export the `.p12`.
3. **Owner** access to the GitHub repository to add encrypted secrets.

---

## Step 1 — Create a Developer ID Application certificate

1. Open **Keychain Access** on a Mac → **Certificate Assistant** → **Request a Certificate From a Certificate Authority**.
2. Use the same email as your Apple Developer account, choose **Saved to disk**.
3. Go to [Apple Developer → Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list) and create a new certificate:
   - Type: **Developer ID Application**
   - Intermediary: **G2 Sub-CA (Xcode 11.4.1 or later)**
   - Upload the `.certSigningRequest` file from step 2.
4. Download the certificate and open it in **Keychain Access**.
5. In Keychain Access, select **both** the certificate and its private key, right-click → **Export 2 items…**.
   - Format: **Personal Information Exchange (.p12)**.
   - Choose a strong export password and save it.
6. Base64-encode the `.p12` for GitHub Actions:

```bash
base64 -i QueryaDeveloperID.p12 -o QueryaDeveloperID.p12.base64
```

Copy the contents of `QueryaDeveloperID.p12.base64`. You will paste it into `MACOS_CERTIFICATE_P12`.

7. Note the **full certificate name**. It looks like:

```
Developer ID Application: Your Name or Org (ABCD123456)
```

You will paste it into `MACOS_SIGN_IDENTITY`.

---

## Step 2 — Create a notarization API key

Using `notarytool` with an App Store Connect API key is the most reliable method in CI.

1. Sign in to [App Store Connect](https://appstoreconnect.apple.com/) with the Apple Developer account.
2. Go to **Users and Access** → **Integrations** → **App Store Connect API**.
3. Create a new **Team Key** (or use an existing one) with the **Admin** or **App Manager** role.
   - Note the **Issuer ID**.
   - Note the **Key ID**.
   - Download the `.p8` file (you can only do this once).
4. Base64-encode the `.p8` file:

```bash
base64 -i AuthKey_KEYID.p8 -o AuthKey_KEYID.p8.base64
```

Copy the contents for `MACOS_NOTARY_KEY`.

---

## Step 3 — Add GitHub Actions secrets

Go to **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret | Value |
|--------|-------|
| `MACOS_CERTIFICATE_P12` | Base64-encoded `.p12` certificate from Step 1 |
| `MACOS_CERTIFICATE_PASSWORD` | The password you set when exporting the `.p12` |
| `MACOS_SIGN_IDENTITY` | Full certificate name, e.g. `Developer ID Application: Querya Team (ABCD123456)` |
| `MACOS_NOTARY_KEY` | Base64-encoded `.p8` API key from Step 2 |
| `MACOS_NOTARY_KEY_ID` | The Key ID from Step 2, e.g. `ABC123DEF4` |
| `MACOS_NOTARY_ISSUER_ID` | The Issuer ID from Step 2, e.g. `12345678-90ab-cdef-1234-567890abcdef` |
| `MACOS_KEYCHAIN_PASSWORD` | A random strong password (it is only used inside the CI runner) |

---

## Step 4 — How the workflow behaves

`.github/workflows/release.yml` contains a `Sign and notarize macOS app` step that runs only when `MACOS_SIGN_IDENTITY` and `MACOS_NOTARY_KEY` are set:

- Creates a temporary keychain in the runner.
- Imports the Developer ID certificate.
- Signs nested frameworks, dylibs, and the main `.app` bundle with the **Hardened Runtime**.
- Applies entitlements from `macos/Runner/Release.entitlements`.
- Submits the app to Apple **notarytool**, waits for approval.
- **Staples** the notarization ticket to the `.app` so it works offline.
- The final zip is then produced from the signed/stapled bundle.

If the secrets are **not** set, the step is skipped and the zip is built exactly as before (unsigned). This keeps the release workflow safe for forks and local testing.

---

## Step 5 — Verify locally (optional)

After a release, download the macOS zip and run:

```bash
# Check the signature
codesign --verify --deep --strict --verbose=2 querya_desktop.app

# Check notarization/staple
spctl --assess --verbose --type execute querya_desktop.app
xcrun stapler validate querya_desktop.app
```

If all three commands report success, the app should open with a normal double-click.

---

## Entitlements

`macos/Runner/Release.entitlements` has been updated for a **Developer ID, non-App-Store** distribution:

- **App Sandbox is disabled** — the app is a database client that needs to connect to arbitrary hosts, read user-selected files, and manage extensions in `~/.querya`.
- **Hardened Runtime** exceptions for Flutter/Dart are enabled (`allow-jit`, `allow-unsigned-executable-memory`, `disable-library-validation`).

If you later add plugins that require microphone, camera, or other protected resources, add the corresponding hardened-runtime and/or sandbox entitlements to this file and re-sign.

---

## References

- Flutter: [Build and release a macOS app](https://docs.flutter.dev/deployment/macos)
- Apple: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- Apple: [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)
- Apple: [Disable Library Validation Entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.disable-library-validation)
