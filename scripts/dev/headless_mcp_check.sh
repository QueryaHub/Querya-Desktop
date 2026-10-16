#!/usr/bin/env bash
# L2 headless MCP end to end: the real app under Xvfb with its MCP server on,
# one fixture SQLite connection shared, and a client talking MCP to it through
# the real `querya-mcp` bridge.
#
#   scripts/dev/headless_mcp_check.sh --mcp PATH [--bundle DIR] [--log FILE]
#
#   --mcp PATH      the querya-mcp executable (dart compile exe
#                   packages/querya_mcp_bridge/bin/querya_mcp.dart -o querya-mcp)
#   --bundle DIR    built bundle, as for headless_app.sh
#   --log FILE      the app's output, as for headless_app.sh
#
# Needs what headless_app.sh needs, plus sqlite3 and python3. Exit codes are
# headless_app.sh's: 0 all checks passed, 1 something failed, 2 usage / tools.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
mcp=""
pass=()
while [ $# -gt 0 ]; do
  case "$1" in
    --mcp) mcp="${2:-}"; shift 2 ;;
    --bundle | --log) pass+=("$1" "${2:-}"); shift 2 ;;
    -h | --help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "headless_mcp_check: unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -x "$mcp" ] || { echo "headless_mcp_check: --mcp must point at the querya-mcp executable" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "headless_mcp_check: python3 is missing" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || { echo "headless_mcp_check: sqlite3 is missing" >&2; exit 2; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/querya-mcp-check.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# The database the model will query.
sqlite3 "$tmp/fixture.db" <<'SQL'
CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, price REAL NOT NULL);
INSERT INTO items (name, price) VALUES ('alpha', 10), ('beta', 20), ('gamma', 30);
SQL

# What the settings page would store: the connection, the server on, the
# connection shared. A second connection stays unshared, so the check can see
# that sharing is opt-in.
cat >"$tmp/seed.sql" <<SQL
INSERT INTO connections (id, type, name, host, created_at)
  VALUES (101, 'sqlite', 'mcp-fixture', '$tmp/fixture.db', datetime('now')),
         (102, 'sqlite', 'not-shared', '$tmp/fixture.db', datetime('now'));
INSERT OR REPLACE INTO app_settings (key, value) VALUES ('mcp_server_enabled', 'true');
INSERT OR REPLACE INTO app_settings (key, value) VALUES ('mcp_read_connection_ids', '[101]');
SQL

status=0
"$here/headless_app.sh" ${pass[@]+"${pass[@]}"} \
  --seed-sql "$tmp/seed.sql" \
  --keep 3 \
  --run "python3 '$here/mcp_stdio_check.py' --mcp '$mcp' --connection mcp-fixture --unshared-id 102" \
  || status=$?
exit "$status"
