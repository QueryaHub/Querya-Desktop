#!/usr/bin/env bash
# Compiles querya-ext-tester to one static executable.
#
#   scripts/ci/build_ext_tester.sh build/ext-tester/querya-ext-tester
#
# `dart compile exe` refuses a package graph that has build hooks (sqlite3,
# objective_c), and the app's graph has them. The tester itself is pure Dart
# (lib/core/extensions + `package:path`), so it is built from a throwaway
# package that is named like the app, holds only lib/core/extensions and
# depends on `path`. Run it from the repository root; the output path is
# relative to it.
set -euo pipefail

OUT="${1:?usage: build_ext_tester.sh <output-file, relative to the repo root>}"
WORK="build/ext-tester-src"

rm -rf "$WORK"
mkdir -p "$WORK/lib/core" "$WORK/bin" "$(dirname "$OUT")"
cp -R lib/core/extensions "$WORK/lib/core/extensions"
cp bin/querya_ext_tester.dart "$WORK/bin/querya_ext_tester.dart"

cat > "$WORK/pubspec.yaml" <<'YAML'
name: querya_desktop
description: Throwaway package that builds querya-ext-tester (see scripts/ci/build_ext_tester.sh).
publish_to: none
environment:
  sdk: '>=3.5.0 <4.0.0'
dependencies:
  path: ^1.9.0
YAML

# The work directory is two levels below the repository root.
(cd "$WORK" && dart pub get && dart compile exe bin/querya_ext_tester.dart -o "../../$OUT")
rm -rf "$WORK"
