#!/usr/bin/env bash
# Build Querya-Desktop-*.AppImage from a Flutter linux release bundle.
#
# Usage:
#   ./scripts/linux/build_appimage.sh [bundle_dir] [output_appimage]
#
# Defaults:
#   bundle_dir = build/linux/x64/release/bundle
#   output     = Querya-Desktop-<pubspec-semver>-linux.AppImage
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="${1:-$ROOT/build/linux/x64/release/bundle}"
BINARY_NAME="querya_desktop"
ICON_SRC="$ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"

if [[ ! -d "$BUNDLE" ]]; then
  echo "error: Flutter linux bundle not found: $BUNDLE" >&2
  echo "Run: flutter build linux --release" >&2
  exit 1
fi
if [[ ! -x "$BUNDLE/$BINARY_NAME" ]]; then
  echo "error: missing executable: $BUNDLE/$BINARY_NAME" >&2
  exit 1
fi
if [[ ! -f "$ICON_SRC" ]]; then
  echo "error: icon not found: $ICON_SRC" >&2
  exit 1
fi

VERSION="$(grep '^version:' "$ROOT/pubspec.yaml" | sed 's/^version: //; s/+.*//')"
OUT="${2:-$ROOT/Querya-Desktop-${VERSION}-linux.AppImage}"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/querya-appimage.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

APPDIR="$WORKDIR/AppDir"
mkdir -p "$APPDIR"
cp -a "$BUNDLE"/. "$APPDIR/"

cp "$ICON_SRC" "$APPDIR/${BINARY_NAME}.png"

cat > "$APPDIR/${BINARY_NAME}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Querya Desktop
Comment=Multi-database desktop client
Exec=${BINARY_NAME}
Icon=${BINARY_NAME}
Categories=Development;Database;
Terminal=false
StartupWMClass=querya_desktop
X-AppImage-Version=${VERSION}
EOF

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/bash
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="${HERE}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
cd "$HERE"
exec "$HERE/querya_desktop" "$@"
EOF
chmod +x "$APPDIR/AppRun" "$APPDIR/$BINARY_NAME"

TOOL="$WORKDIR/appimagetool"
# Prefer type-2 continuous tool; --appimage-extract-and-run avoids FUSE on CI.
curl -fsSL -o "$TOOL" \
  "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x "$TOOL"

ARCH=x86_64 "$TOOL" --appimage-extract-and-run "$APPDIR" "$OUT"
chmod +x "$OUT"
echo "Wrote $OUT"
