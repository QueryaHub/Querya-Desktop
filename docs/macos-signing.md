# macOS signing and notarization (future track)

CI currently produces a **macOS zip** with an **unsigned** `.app`. Users may need to use **Open** from the context menu the first time, or adjust Gatekeeper settings.

## Goal for broader distribution

1. **Apple Developer Program** membership and certificates (Developer ID Application).
2. **Code sign** the app bundle and nested frameworks (`flutter build macos` output).
3. **Notarize** with `notarytool` / `xcrun notarytool`, then staple the ticket.
4. Store signing secrets in **GitHub Actions** encrypted secrets; run signing in `release.yml` only on protected branches/tags.

## References

- Flutter: [Build and release a macOS app](https://docs.flutter.dev/deployment/macos)
- Apple: notarization and hardened runtime requirements

This repository does not yet automate signing; treat this file as a checklist when the project is ready to invest in that workflow.
