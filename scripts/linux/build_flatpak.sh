#!/usr/bin/env bash
# Build Querya-Desktop-*.flatpak from a Flutter linux release bundle.
#
# Usage:
#   ./scripts/linux/build_flatpak.sh [bundle_dir] [output_flatpak]
#
# Requires: flatpak, flatpak-builder, Flathub org.gnome.Platform + org.gnome.Sdk
# (matching runtime-version in packaging/linux/flatpak/com.queryahub.querya_desktop.yml).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="${1:-$ROOT/build/linux/x64/release/bundle}"
BINARY_NAME="querya_desktop"
ICON_SRC="$ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"
APP_ID="com.queryahub.querya_desktop"
MANIFEST_SRC="$ROOT/packaging/linux/flatpak/${APP_ID}.yml"
DESKTOP_SRC="$ROOT/packaging/linux/flatpak/${APP_ID}.desktop"

if [[ ! -d "$BUNDLE" ]]; then
  echo "error: Flutter linux bundle not found: $BUNDLE" >&2
  exit 1
fi
if [[ ! -x "$BUNDLE/$BINARY_NAME" ]]; then
  echo "error: missing executable: $BUNDLE/$BINARY_NAME" >&2
  exit 1
fi
if ! command -v flatpak-builder >/dev/null 2>&1; then
  echo "error: flatpak-builder is required" >&2
  exit 1
fi

VERSION="$(grep '^version:' "$ROOT/pubspec.yaml" | sed 's/^version: //; s/+.*//')"
OUT="${2:-$ROOT/Querya-Desktop-${VERSION}-linux.flatpak}"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/querya-flatpak.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

STAGING="$WORKDIR/staging"
BUILD_DIR="$WORKDIR/build"
REPO="$WORKDIR/repo"
STATE="$WORKDIR/state"

mkdir -p "$STAGING/bundle"
cp -a "$BUNDLE"/. "$STAGING/bundle/"
cp "$MANIFEST_SRC" "$STAGING/${APP_ID}.yml"
cp "$DESKTOP_SRC" "$STAGING/bundle/${APP_ID}.desktop"
cp "$ICON_SRC" "$STAGING/bundle/${APP_ID}.png"

flatpak-builder \
  --force-clean \
  --repo="$REPO" \
  --state-dir="$STATE" \
  "$BUILD_DIR" \
  "$STAGING/${APP_ID}.yml"

flatpak build-bundle "$REPO" "$OUT" "$APP_ID"
echo "Wrote $OUT"
