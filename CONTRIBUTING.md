# Contributing

## Flutter version

CI pins a **stable** Flutter version in [`.github/workflows/ci.yml`](.github/workflows/ci.yml) and [`.github/workflows/release.yml`](.github/workflows/release.yml). Prefer matching that version locally to avoid “works on my machine” drift. When bumping the pin, run `flutter test` and a release smoke build before merging.

## Linux: `flutter analyze` and “Too many open files”

On some Linux setups the Dart analysis server hits the process **open file limit** (`errno = 24`). Try:

```bash
ulimit -n 8192
flutter analyze
```

## Git tags and release commits

A **tag points at one commit**. Release artifacts are built from the tree at that commit. If you fix something **after** pushing a release tag, either:

- move the tag to the new commit (only if the team agrees and the release is not yet consumed), or  
- ship a **new** semver (update `pubspec.yaml` / `CHANGELOG.md`) and push a **new** tag.

See [docs/tags-and-releases.md](docs/tags-and-releases.md).

## Tests

```bash
flutter pub get
flutter test
```

Widget tests that use SQLite or `path_provider` follow patterns in `test/features/connections/connections_panel_layout_test.dart` and `test/flutter_test_config.dart` (in-memory secrets backend).
