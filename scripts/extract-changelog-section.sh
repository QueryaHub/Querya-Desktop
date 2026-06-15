#!/usr/bin/env bash
# Extract one Keep a Changelog section from CHANGELOG.md by semver (e.g. 0.4.3 or v0.4.3).
set -euo pipefail

VERSION="${1:?usage: extract-changelog-section.sh <version> [changelog-file]}"
CHANGELOG="${2:-CHANGELOG.md}"

VERSION="${VERSION#v}"

if [[ ! -f "$CHANGELOG" ]]; then
  echo "error: changelog not found: $CHANGELOG" >&2
  exit 1
fi

awk -v ver="$VERSION" '
BEGIN { found = 0; capture = 0 }
/^## \[/ {
  if (capture) exit
  if ($0 ~ "^## \\[" ver "\\]") {
    found = 1
    capture = 1
    print
    next
  }
}
capture { print }
END {
  if (!found) {
    print "error: no changelog section for version " ver " in " FILENAME > "/dev/stderr"
    exit 1
  }
}
' "$CHANGELOG"
