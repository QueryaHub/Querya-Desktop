# Contributing

Thanks for your interest in improving Querya Desktop. This guide covers the
workflow, branch/commit conventions, and the checks we expect before a PR.

New to the codebase? Start with [docs/getting-started.md](docs/getting-started.md)
and [docs/architecture.md](docs/architecture.md).

## Workflow

We follow a simple GitFlow: feature work branches off `dev` and merges back into
`dev` via PR; `main` holds production-ready code and release tags.

```bash
# 1. Sync
git fetch --all --prune
git checkout dev
git pull --ff-only origin dev

# 2. Branch (one issue → one branch → one PR)
git checkout -b issue/<number>-<short-slug>     # or feat/<short-slug>

# 3. ...make changes, then run the checks below...

# 4. Open a PR into `dev` with "Closes #<number>" in the body
```

Keep each PR scoped to a single issue — avoid drive-by refactoring.

## Commits

We use [Conventional Commits](https://www.conventionalcommits.org/):
`feat`, `fix`, `perf`, `docs`, `test`, `ci`, `chore`, `refactor`, with a scope
where helpful (`postgresql`, `mysql`, `mongodb`, `redis`, `connections`, `theme`,
`editor`, `settings`, `ui`, `ci`, `deps`).

```
feat(theme): add QueryaWorkbenchTheme and editor tokens
fix(postgresql): pass right-clicked table into Open in SQL
docs: restructure README and docs index
```

**Never commit** secrets — `.env`, keys, `credentials.json`, or exported
connection secrets.

## Checks before a PR

Run the same checks CI runs:

```bash
flutter pub get
flutter analyze
flutter test
```

For release or large UI PRs, optionally smoke-test a build:

```bash
flutter build linux --release   # or windows / macos
```

### Linux: `flutter analyze` and "Too many open files"

On some Linux setups the Dart analysis server hits the process **open file
limit** (`errno = 24`). Raise it for the session:

```bash
ulimit -n 8192
flutter analyze
```

## Flutter version

CI pins a **stable** Flutter version in
[`.github/workflows/ci.yml`](.github/workflows/ci.yml) and
[`.github/workflows/release.yml`](.github/workflows/release.yml). Match that
version locally to avoid "works on my machine" drift. When bumping the pin, run
`flutter test` and a release smoke build before merging.

## Tests

Widget tests that use SQLite or `path_provider` follow patterns in
`test/features/connections/connections_panel_layout_test.dart` and
`test/flutter_test_config.dart` (in-memory secrets backend). Mirror `lib/` layout
under `test/` where possible.

## Releases and tags

A **tag points at one commit**, and release artifacts are built from that tree.
If you fix something **after** pushing a release tag, either move the tag (only if
the team agrees and the release is not yet consumed) or ship a **new** semver
(update `pubspec.yaml` / `CHANGELOG.md`) and push a new tag. See
[docs/tags-and-releases.md](docs/tags-and-releases.md) and
[docs/release-checklist.md](docs/release-checklist.md).
