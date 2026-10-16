#!/usr/bin/env bash
# Scenario "pinned": version 0.4.19, the oldest supported tester.
set -e
source dev-container-features-test-lib

check "tester is on PATH" command -v querya-ext-tester
check "tester prints usage" bash -c 'querya-ext-tester --help | grep -q "Usage: querya-ext-tester"'

reportResults
