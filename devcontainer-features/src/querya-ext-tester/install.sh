#!/usr/bin/env bash
# Installs querya-ext-tester from a Querya Desktop release and checks the
# archive against the SHA256SUMS.txt published with that release.
set -euo pipefail

REPO="QueryaHub/Querya-Desktop"
MIN_VERSION="0.4.19" # earlier testers ignored the exit code of main()
REQUESTED="${VERSION:-latest}"
DEST="${QUERYA_EXT_TESTER_DEST:-/usr/local/bin/querya-ext-tester}"

fail() { echo "querya-ext-tester feature: $*" >&2; exit 1; }

ensure_tools() {
  local missing=()
  for tool in curl tar sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  [ ${#missing[@]} -eq 0 ] && return 0
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y --no-install-recommends curl ca-certificates tar coreutils
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl ca-certificates tar coreutils
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl ca-certificates tar coreutils
  else
    fail "missing ${missing[*]} and no known package manager to install them"
  fi
}

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) TARGET="linux-x64" ;;
  *) fail "only Linux x86_64 is released ($(uname -s)-$(uname -m))" ;;
esac

ensure_tools

if [ "$REQUESTED" = "latest" ]; then
  # The redirect avoids the API and its unauthenticated rate limit.
  TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
  TAG="${TAG##*/}"
else
  TAG="${REQUESTED#v}"
fi
VERSION_NUMBER="${TAG#v}"
[[ "$VERSION_NUMBER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "cannot read a version from '${TAG}'"

if [ "$(printf '%s\n%s\n' "$MIN_VERSION" "$VERSION_NUMBER" | sort -V | head -n1)" != "$MIN_VERSION" ]; then
  fail "querya-ext-tester ${VERSION_NUMBER} is older than ${MIN_VERSION}; its exit codes are not reliable"
fi

ASSET="querya-ext-tester-v${VERSION_NUMBER}-${TARGET}.tar.gz"
BASE="https://github.com/${REPO}/releases/download/${TAG}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading ${ASSET} from release ${TAG}"
curl -fsSL -o "${WORK}/${ASSET}" "${BASE}/${ASSET}" || fail "cannot download ${BASE}/${ASSET}"
curl -fsSL -o "${WORK}/SHA256SUMS.txt" "${BASE}/SHA256SUMS.txt" || fail "cannot download ${BASE}/SHA256SUMS.txt"

EXPECTED="$(grep " ${ASSET}\$" "${WORK}/SHA256SUMS.txt" | cut -d' ' -f1 || true)"
[ -n "$EXPECTED" ] || fail "${ASSET} is not listed in SHA256SUMS.txt of ${TAG}"
ACTUAL="$(sha256sum "${WORK}/${ASSET}" | cut -d' ' -f1)"
[ "$EXPECTED" = "$ACTUAL" ] || fail "checksum mismatch for ${ASSET}"

tar -xzf "${WORK}/${ASSET}" -C "$WORK"
install -m 0755 "${WORK}/querya-ext-tester" "$DEST"

"$DEST" --help | grep -q "Usage: querya-ext-tester" || fail "installed binary does not run"
echo "Installed querya-ext-tester ${VERSION_NUMBER}"
