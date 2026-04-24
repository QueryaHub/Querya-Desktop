# Pre-release checklist (toward 1.0)

Use this before tagging or running the **Release** workflow.

## Product smoke (manual)

- [ ] Fresh profile / empty state: create one connection per supported type (PostgreSQL, MySQL, Redis, MongoDB).
- [ ] Reopen the app: connections still appear; **connect** succeeds (secrets migrated or loaded from secure store).
- [ ] Remove a connection: it disappears and reconnect is impossible without re-entering credentials.
- [ ] **Connection → New Database Connection** from the menu saves and shows in the tree.
- [ ] **Driver Manager** shows only built-in drivers (no misleading JDBC requirement).

## Automated

- [ ] `flutter analyze` — clean.
- [ ] `flutter test` — all green.

## Versioning and release

- [ ] `pubspec.yaml` `version` matches the release you intend to ship.
- [ ] Run the **Release** workflow from GitHub Actions (see [tags-and-releases.md](tags-and-releases.md)).
- [ ] Verify **Linux** and **Windows** zip artifacts and `SHA256SUMS.txt` on the GitHub Release.

## Docs

- [ ] [security.md](security.md) still matches behavior if storage changed.
- [ ] [README.md](../README.md) prerequisites (e.g. Linux deps) still accurate.
