#!/usr/bin/env bash
# Prepares beta N of version X.Y.Z on a release branch (#1498):
#   - pubspec:   version: X.Y.Z-beta.N+<build + 1>
#   - CHANGELOG: a "## [X.Y.Z-beta.N] - <today>" heading under "## [Unreleased]",
#                so what was unreleased becomes the beta's notes
# and prints the commands to check, commit and tag. Commits and pushes nothing.
#
#   scripts/release/prepare_beta.sh 0.5.0 1
#
# QUERYA_RELEASE_ROOT points at another checkout (tests).
set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: $0 <X.Y.Z> <N>" >&2; exit 2; }
BASE="$1"
N="$2"
[[ "$BASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: '$BASE' is not X.Y.Z" >&2; exit 2; }
[[ "$N" =~ ^[1-9][0-9]*$ ]] || { echo "error: '$N' is not a beta number (1, 2, ...)" >&2; exit 2; }

ROOT="${QUERYA_RELEASE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
VERSION="$BASE-beta.$N"
PUBSPEC="$ROOT/pubspec.yaml"
CHANGELOG="$ROOT/CHANGELOG.md"

LINE="$(grep '^version:' "$PUBSPEC" | sed 's/^version:[[:space:]]*//')"
BUILD=0
[[ "$LINE" == *+* ]] && BUILD="${LINE##*+}"
[[ "$BUILD" =~ ^[0-9]+$ ]] || BUILD=0
NEW="$VERSION+$((BUILD + 1))"

if grep -q "^## \[$VERSION\]" "$CHANGELOG"; then
  echo "error: CHANGELOG.md already has ## [$VERSION]" >&2
  exit 1
fi
if ! grep -q '^## \[Unreleased\]' "$CHANGELOG"; then
  echo "error: CHANGELOG.md has no '## [Unreleased]' heading to put the beta under" >&2
  exit 1
fi

sed -i.bak "s/^version: .*/version: $NEW/" "$PUBSPEC" && rm -f "$PUBSPEC.bak"
TODAY="$(date +%Y-%m-%d)"
awk -v heading="## [$VERSION] - $TODAY" '
  { print }
  /^## \[Unreleased\]/ && !done { print ""; print heading; done = 1 }
' "$CHANGELOG" > "$CHANGELOG.tmp" && mv "$CHANGELOG.tmp" "$CHANGELOG"

cat <<MSG
pubspec.yaml:  version: $NEW
CHANGELOG.md:  ## [$VERSION] - $TODAY (the notes under it were [Unreleased])

Next, on the release branch:
  scripts/release/check_release.sh $VERSION
  git commit -am "release: $VERSION"
  git tag -a $VERSION -m "Querya Desktop $VERSION"
  git push origin HEAD $VERSION
MSG
