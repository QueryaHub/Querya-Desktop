#!/usr/bin/env bash
# Build Querya-Desktop-*.deb from a Flutter linux release bundle (Debian/Ubuntu).
#
# Usage:
#   ./scripts/linux/build_deb.sh [bundle_dir] [output_deb]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="${1:-$ROOT/build/linux/x64/release/bundle}"
BINARY_NAME="querya_desktop"
ICON_SRC="$ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"

if [[ ! -d "$BUNDLE" ]]; then
  echo "error: Flutter linux bundle not found: $BUNDLE" >&2
  exit 1
fi
if [[ ! -x "$BUNDLE/$BINARY_NAME" ]]; then
  echo "error: missing executable: $BUNDLE/$BINARY_NAME" >&2
  exit 1
fi
if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "error: dpkg-deb is required (apt install dpkg)" >&2
  exit 1
fi

VERSION="$(grep '^version:' "$ROOT/pubspec.yaml" | sed 's/^version: //; s/+.*//')"
OUT="${2:-$ROOT/Querya-Desktop-${VERSION}-linux.deb}"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/querya-deb.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

PKG="$WORKDIR/pkg"
INSTALL_ROOT="$PKG/opt/querya-desktop"
mkdir -p \
  "$INSTALL_ROOT" \
  "$PKG/usr/bin" \
  "$PKG/usr/share/applications" \
  "$PKG/usr/share/icons/hicolor/512x512/apps" \
  "$PKG/DEBIAN"

cp -a "$BUNDLE"/. "$INSTALL_ROOT/"
chmod +x "$INSTALL_ROOT/$BINARY_NAME"

ln -s "/opt/querya-desktop/$BINARY_NAME" "$PKG/usr/bin/$BINARY_NAME"

if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$PKG/usr/share/icons/hicolor/512x512/apps/${BINARY_NAME}.png"
fi

cp "$ROOT/packaging/linux/querya_desktop.desktop" \
  "$PKG/usr/share/applications/${BINARY_NAME}.desktop"

# Rough installed size in KiB for the control file.
INSTALLED_SIZE="$(du -sk "$PKG" | awk '{print $1}')"

cat > "$PKG/DEBIAN/control" <<EOF
Package: querya-desktop
Version: ${VERSION}
Section: database
Priority: optional
Architecture: ${ARCH}
Maintainer: QueryaHub <noreply@querya.app>
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0, libsecret-1-0, libglib2.0-0
Recommends: libayatana-appindicator3-1
Homepage: https://github.com/QueryaHub/Querya-Desktop
Description: Querya Desktop database client
 Multi-database desktop client for PostgreSQL, MySQL, Redis, MongoDB,
 SQLite, and sandboxed drivers.
EOF

dpkg-deb --root-owner-group --build "$PKG" "$OUT"
echo "Wrote $OUT"
