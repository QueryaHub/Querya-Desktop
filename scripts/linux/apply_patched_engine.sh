#!/usr/bin/env bash
# Splice the vsync-patched libflutter_linux_gtk.so (QueryaHub/flutter-engine-linux-120hz)
# into a Linux release bundle, in place of the stock engine.
#
# Why: on Linux, Flutter's GTK embedder has no vsync callback and hard-codes a
# 60 Hz frame pacer, so the app never exceeds 60 fps even on a 90/120/144 Hz
# monitor (querya-desktop#980, upstream flutter/flutter#192342). The patched
# engine fixes this; see that repo's README for what's patched and why.
#
# Usage:
#   ./scripts/linux/apply_patched_engine.sh [bundle_dir]
#
# Defaults: bundle_dir = build/linux/x64/release/bundle
#
# The patched .so only works with the exact engine ABI it was built against,
# keyed by Flutter's own "engine content hash" (`flutter --version`'s
# "Engine • hash <content_hash> (revision ...)" line). If no matching release
# exists in the engine repo yet (e.g. Flutter was just bumped and nobody
# rebuilt the patched engine for the new content hash), this script WARNS and
# leaves the stock engine in place — it must never fail the build over this.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="${1:-$ROOT/build/linux/x64/release/bundle}"
ENGINE_REPO="QueryaHub/flutter-engine-linux-120hz"
TARGET_SO="$BUNDLE/lib/libflutter_linux_gtk.so"

warn_stock() {
  echo "::warning::apply_patched_engine.sh: $1 — shipping stock Linux engine (capped at 60 fps, querya-desktop#980)." >&2
}

if [[ ! -f "$TARGET_SO" ]]; then
  warn_stock "no bundle at $TARGET_SO (run flutter build linux --release first)"
  exit 0
fi

if ! command -v flutter >/dev/null 2>&1; then
  warn_stock "flutter not on PATH, cannot resolve engine content hash"
  exit 0
fi

CONTENT_HASH="$(flutter --version 2>/dev/null | sed -n 's/.*Engine .*hash \([0-9a-f]*\).*/\1/p')"
if [[ -z "$CONTENT_HASH" ]]; then
  warn_stock "could not parse engine content hash from 'flutter --version'"
  exit 0
fi

TAG="engine-${CONTENT_HASH}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

if ! gh release download "$TAG" \
    --repo "$ENGINE_REPO" \
    --pattern "libflutter_linux_gtk-release.so.gz" \
    --dir "$WORKDIR" >/dev/null 2>&1; then
  warn_stock "no patched engine published for content hash $CONTENT_HASH (tag $TAG in $ENGINE_REPO) — rebuild it there first"
  exit 0
fi

gunzip -f "$WORKDIR/libflutter_linux_gtk-release.so.gz"
cp "$WORKDIR/libflutter_linux_gtk-release.so" "$TARGET_SO"
echo "apply_patched_engine.sh: spliced in vsync-patched engine for content hash $CONTENT_HASH ($TAG)."
