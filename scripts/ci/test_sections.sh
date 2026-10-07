#!/usr/bin/env bash
# Splits the Flutter test suite into independent sections that CI runs in
# parallel jobs (see .github/workflows/ci.yml).
#
#   scripts/ci/test_sections.sh list            # section names, one per line
#   scripts/ci/test_sections.sh paths <name>    # test paths of one section
#   scripts/ci/test_sections.sh check           # every test file is in exactly one section
#
# A section is a set of test directories. The `rest` section is everything no
# other section claims, so a test added in a new directory is still run.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

declare -A SECTIONS=(
  [core-data]="test/core/database test/core/storage test/core/security test/core/actions test/core/app test/core/json test/core/csv test/core/util"
  [core-extensions]="test/core/extensions test/core/market test/core/sdui test/core/updater test/features/extensions test/features/updater"
  [core-theme]="test/core/theme test/shared"
  [core-ui]="test/core/motion test/core/layout test/core/ui test/core/editor test/core/widgets test/core/platform test/core/demo"
  [features-workspace]="test/features/workspace test/features/sql_workspaces test/features/sqlite test/features/mysql test/features/postgresql"
  [features-nosql]="test/features/mongodb test/features/redis test/features/nosql"
  [features-app]="test/features/main_screen test/features/connections test/features/settings test/features/command_palette test/features/onboarding test/features/macos test/features/help"
)
ORDER=(core-data core-extensions core-theme core-ui features-workspace features-nosql features-app rest)

all_tests() { find test -name '*_test.dart' | LC_ALL=C sort; }

claimed_dirs() {
  local s
  for s in "${!SECTIONS[@]}"; do echo "${SECTIONS[$s]}"; done | tr ' ' '\n'
}

section_files() {
  local name="$1"
  if [[ "$name" == "rest" ]]; then
    local f d claimed
    mapfile -t claimed < <(claimed_dirs)
    while IFS= read -r f; do
      local hit=0
      for d in "${claimed[@]}"; do
        [[ "$f" == "$d/"* ]] && { hit=1; break; }
      done
      (( hit )) || echo "$f"
    done < <(all_tests)
    return
  fi
  [[ -n "${SECTIONS[$name]:-}" ]] || { echo "unknown section: $name" >&2; exit 2; }
  local d
  for d in ${SECTIONS[$name]}; do
    [[ -d "$d" ]] && find "$d" -name '*_test.dart'
  done | LC_ALL=C sort
}

case "${1:-}" in
  list)
    printf '%s\n' "${ORDER[@]}"
    ;;
  paths)
    [[ -n "${2:-}" ]] || { echo "usage: $0 paths <section>" >&2; exit 2; }
    # Directories keep the command line short; `rest` needs explicit files.
    if [[ "$2" == "rest" ]]; then
      section_files rest
    else
      for d in ${SECTIONS[$2]:-}; do [[ -d "$d" ]] && echo "$d"; done
    fi
    ;;
  check)
    total=$(all_tests | wc -l)
    sum=0
    declare -A seen=()
    for s in "${ORDER[@]}"; do
      n=0
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        if [[ -n "${seen[$f]:-}" ]]; then
          echo "in two sections: $f ($s and ${seen[$f]})" >&2; exit 1
        fi
        seen[$f]="$s"; n=$((n + 1))
      done < <(section_files "$s")
      printf '%-20s %3d test files\n' "$s" "$n"
      sum=$((sum + n))
    done
    echo "total ${sum} of ${total}"
    [[ "$sum" -eq "$total" ]] || { echo "some test files are in no section" >&2; exit 1; }
    ;;
  *)
    echo "usage: $0 {list|paths <section>|check}" >&2; exit 2
    ;;
esac
