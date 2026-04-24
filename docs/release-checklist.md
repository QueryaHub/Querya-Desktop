# Pre-release checklist (toward 1.0)

Use this before tagging or running the **Release** workflow.

## Product smoke (manual)

- [ ] Fresh profile / empty state: create one connection per supported type (PostgreSQL, MySQL, Redis, MongoDB).
- [ ] Reopen the app: connections still appear; **connect** succeeds (secrets migrated or loaded from secure store).
- [ ] Remove a connection: it disappears and reconnect is impossible without re-entering credentials.
- [ ] **Connection → New Database Connection** from the menu saves and shows in the tree.
- [ ] **Driver Manager** shows only built-in drivers (no misleading JDBC requirement).

## Automated

- [ ] `flutter analyze` — clean (on Linux, if the analyzer crashes with **Too many open files**, try `ulimit -n 8192`; see [CONTRIBUTING.md](../CONTRIBUTING.md)).
- [ ] `flutter test` — all green.
- [ ] CI **Flutter version** in `.github/workflows/*.yml` matches the toolchain you validated (bump intentionally when upgrading stable).

## Versioning and release

- [ ] `pubspec.yaml` `version` matches the release you intend to ship.
- [ ] **Tag** is placed on the **commit that includes all fixes** you want in binaries (a tag does not auto-include later commits; see [CONTRIBUTING.md](../CONTRIBUTING.md)).
- [ ] Run the **Release** workflow from GitHub Actions (see [tags-and-releases.md](tags-and-releases.md)).
- [ ] Verify **Linux** and **Windows** zip artifacts and `SHA256SUMS.txt` on the GitHub Release.

## Docs

- [ ] [security.md](security.md) still matches behavior if storage changed.
- [ ] [README.md](../README.md) prerequisites (e.g. Linux deps) still accurate.
- [ ] [roadmap.md](roadmap.md) updated if you are communicating upcoming themes externally.
