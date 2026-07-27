#!/usr/bin/env bash
# Build Querya-Desktop-*.rpm from a Flutter linux release bundle (Fedora/RHEL/openSUSE).
#
# Usage:
#   ./scripts/linux/build_rpm.sh [bundle_dir] [output_rpm]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="${1:-$ROOT/build/linux/x64/release/bundle}"
BINARY_NAME="querya_desktop"
ICON_SRC="$ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"
DESKTOP_FILE="$ROOT/packaging/linux/querya_desktop.desktop"
SPEC="$ROOT/packaging/linux/querya-desktop.spec"

if [[ ! -d "$BUNDLE" ]]; then
  echo "error: Flutter linux bundle not found: $BUNDLE" >&2
  exit 1
fi
if [[ ! -x "$BUNDLE/$BINARY_NAME" ]]; then
  echo "error: missing executable: $BUNDLE/$BINARY_NAME" >&2
  exit 1
fi
if [[ ! -f "$DESKTOP_FILE" ]]; then
  echo "error: desktop file not found: $DESKTOP_FILE" >&2
  exit 1
fi
if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "error: rpmbuild is required (dnf install rpm-build / apt install rpm)" >&2
  exit 1
fi

VERSION="$(grep '^version:' "$ROOT/pubspec.yaml" | sed 's/^version: //; s/+.*//')"
# RPM Version must not contain '-' (it separates Version from Release).
# Keep artifact filename as the pubspec/marketing version (e.g. 0.4.11-b).
RPM_VERSION="${VERSION//-/.}"
OUT="${2:-$ROOT/Querya-Desktop-${VERSION}-linux.rpm}"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/querya-rpm.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

RPM_TOP="$WORKDIR/rpm"
mkdir -p "$RPM_TOP"/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}

rpmbuild -bb "$SPEC" \
  --define "_topdir $RPM_TOP" \
  --define "version $RPM_VERSION" \
  --define "querya_bundle $BUNDLE" \
  --define "querya_icon $ICON_SRC" \
  --define "querya_desktop_file $DESKTOP_FILE"

BUILT="$(find "$RPM_TOP/RPMS" -name 'querya-desktop-*.rpm' | head -n 1)"
if [[ -z "$BUILT" || ! -f "$BUILT" ]]; then
  echo "error: rpmbuild did not produce an RPM under $RPM_TOP/RPMS" >&2
  exit 1
fi

cp "$BUILT" "$OUT"
echo "Wrote $OUT"
