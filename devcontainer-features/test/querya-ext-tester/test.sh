#!/usr/bin/env bash
# Default scenario: the Feature with its default options (latest release).
set -e
source dev-container-features-test-lib

check "tester is on PATH" command -v querya-ext-tester
check "tester prints usage" bash -c 'querya-ext-tester --help | grep -q "Usage: querya-ext-tester"'
check "tester fails on an empty directory" bash -c 'd=$(mktemp -d); ! querya-ext-tester "$d" --no-color'

reportResults
