#!/usr/bin/env bash
# Checks that a release tag can be pushed: the things the Release workflow
# needs, checked before the tag instead of failing in "Publish GitHub Release"
# afterwards (#1498).
#
#   scripts/release/check_release.sh 0.5.0-beta.1
#   scripts/release/check_release.sh v0.5.0 --no-tag-check   # tag already exists (CI)
#
# Checks: the tag is SemVer (X.Y.Z or X.Y.Z-pre); pubspec's version without
# `+build` equals the tag without `v`; a pre-release has a build number in
# pubspec; CHANGELOG.md has `## [<version>]`; the tag is not used yet.
# Then prints what the workflow will do with it. Exits 1 on any problem.
#
# QUERYA_RELEASE_ROOT points at another checkout (tests).
set -euo pipefail

usage() { echo "usage: $0 <tag> [--no-tag-check]" >&2; exit 2; }
[[ $# -ge 1 ]] || usage
TAG="$1"
TAG_CHECK=1
[[ "${2:-}" == "--no-tag-check" ]] && TAG_CHECK=0

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${QUERYA_RELEASE_ROOT:-$(cd "$SCRIPTS/.." && pwd)}"
VERSION="${TAG#v}"
problems=0
fail() { echo "✗ $*"; problems=$((problems + 1)); }
ok() { echo "✓ $*"; }

if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  ok "tag $TAG is a release version"
else
  fail "tag $TAG is not X.Y.Z or X.Y.Z-<pre-release> (letters, digits and dots)"
fi
PRERELEASE=0
[[ "$VERSION" == *-* ]] && PRERELEASE=1

LINE="$(grep '^version:' "$ROOT/pubspec.yaml" | sed 's/^version:[[:space:]]*//')"
SEMVER="${LINE%%+*}"
BUILD=""
[[ "$LINE" == *+* ]] && BUILD="${LINE##*+}"
if [[ "$SEMVER" == "$VERSION" ]]; then
  ok "pubspec version $LINE matches the tag"
else
  fail "pubspec says $LINE; set 'version: $VERSION+<build>' (the artifacts are named after pubspec)"
fi
if (( PRERELEASE )) && ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
  fail "a pre-release needs a build number in pubspec: 'version: $VERSION+<n>'"
fi

if "$SCRIPTS/extract-changelog-section.sh" "$VERSION" "$ROOT/CHANGELOG.md" >/dev/null 2>&1; then
  ok "CHANGELOG.md has ## [$VERSION]"
else
  fail "CHANGELOG.md has no '## [$VERSION]' section (Publish GitHub Release reads it)"
fi

if (( TAG_CHECK )); then
  if git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    fail "tag $TAG already exists"
  else
    ok "tag $TAG is not used yet"
  fi
fi

echo
if (( PRERELEASE )); then
  echo "The Release workflow will publish a GitHub pre-release (not 'latest'):"
  echo "  offered in the app only on the Beta / Early Access channel;"
  echo "  AUR and the APT / DNF repositories are skipped."
else
  echo "The Release workflow will publish a stable release and make it 'latest':"
  echo "  offered on both channels; AUR and APT / DNF are published (when their secrets are set)."
fi

if (( problems )); then
  echo
  echo "$problems problem(s): fix them before pushing the tag."
  exit 1
fi
