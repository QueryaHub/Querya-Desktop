#!/usr/bin/env bash
# The version string a .deb / .rpm carries for a pubspec version (#1494).
#
#   ./scripts/linux/package_version.sh 0.5.0-beta.1   # -> 0.5.0~beta.1
#
# or `source` it and call `package_version`.
#
# A SemVer pre-release must sort *before* its final release. As is, dpkg reads
# `0.5.0-beta.1` as upstream 0.5.0 with revision `beta.1`, newer than `0.5.0`,
# and rpm's `0.5.0.beta.1` is newer too, so beta users would never be upgraded
# to the final package. Both sort `~` before anything, even the end of the
# string: `0.5.0~beta.1 < 0.5.0`. Any further `-` becomes `.`, since `-`
# separates the Debian revision and the RPM release.

package_version() {
  printf '%s\n' "$1" | sed 's/-/~/; s/-/./g'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  package_version "${1:?usage: package_version.sh <version>}"
fi
