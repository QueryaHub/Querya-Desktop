#!/usr/bin/env bash
# L2 headless run: the real Querya app under a virtual display, in portable
# mode, on a throw-away data directory. No window server or GPU is needed.
#
#   scripts/dev/headless_app.sh [options]
#
#   --bundle DIR        built bundle (default: build/linux/x64/release/bundle,
#                       then .../debug/bundle); must contain `querya_desktop`
#   --screenshot FILE   save a screenshot of the virtual screen (PNG)
#   --wait SECONDS      how long to wait for the window (default 60)
#   --keep SECONDS      how long it has to stay alive after the window shows up
#                       (default 3); catches crashes right after start
#   --log FILE          copy the app's stdout / stderr there
#   --keep-data         do not delete the temporary data directory
#   --seed-sql FILE     SQL applied to the profile database (querya.db) before
#                       the app under test starts: the app runs once to create
#                       and migrate the database, is stopped, FILE is applied
#                       with sqlite3, and the app starts again
#   --run COMMAND       shell command to run once the window is up (the app
#                       stays up meanwhile); the exit code is its exit code.
#                       Gets QUERYA_MCP_ENDPOINT (this run's own endpoint file),
#                       QUERYA_HEADLESS_DB and QUERYA_HEADLESS_DATA
#   -h, --help          this text
#
# Exit codes: 0 the app started, showed a window and stayed up (and --run
# succeeded); 1 it died, no window appeared in time, or --run failed; 2 usage
# error, missing bundle or missing tool.
#
# Needs: Xvfb; xdotool or xwininfo to see the window (without them the check is
# "the process is still alive after --wait"); ImageMagick `import` for
# --screenshot. Environment: QUERYA_HEADLESS_DISPLAY to force a display number.
set -u

bundle=""
screenshot=""
wait_s=60
keep_s=3
log_out=""
keep_data=0
seed_sql=""
run_cmd=""

usage() { sed -n '2,/^set -u/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
die() { printf 'headless_app: %s\n' "$*" >&2; exit 2; }
say() { printf 'headless_app: %s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --bundle) bundle="${2:-}"; shift 2 ;;
    --screenshot) screenshot="${2:-}"; shift 2 ;;
    --wait) wait_s="${2:-}"; shift 2 ;;
    --keep) keep_s="${2:-}"; shift 2 ;;
    --log) log_out="${2:-}"; shift 2 ;;
    --keep-data) keep_data=1; shift ;;
    --seed-sql) seed_sql="${2:-}"; shift 2 ;;
    --run) run_cmd="${2:-}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

if [ -z "$bundle" ]; then
  for candidate in build/linux/x64/release/bundle build/linux/x64/debug/bundle; do
    if [ -x "$candidate/querya_desktop" ]; then bundle="$candidate"; break; fi
  done
fi
[ -n "$bundle" ] || die "no bundle found; build one (flutter build linux) or pass --bundle DIR"
[ -x "$bundle/querya_desktop" ] || die "$bundle/querya_desktop is missing or not executable"
command -v Xvfb >/dev/null 2>&1 || die "Xvfb is not installed (apt-get install xvfb)"
if [ -n "$seed_sql" ]; then
  [ -f "$seed_sql" ] || die "--seed-sql: $seed_sql is not a file"
  command -v sqlite3 >/dev/null 2>&1 || die "--seed-sql needs the sqlite3 command (apt-get install sqlite3)"
fi
if [ -n "$screenshot" ] && ! command -v import >/dev/null 2>&1; then
  die "--screenshot needs ImageMagick's 'import' (apt-get install imagemagick)"
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/querya-headless.XXXXXX")"
app_pid=""
xvfb_pid=""

cleanup() {
  local status=$?
  if [ -n "$app_pid" ] && kill -0 "$app_pid" 2>/dev/null; then
    kill -TERM "$app_pid" 2>/dev/null
    for _ in $(seq 1 20); do
      kill -0 "$app_pid" 2>/dev/null || break
      sleep 0.5
    done
    kill -KILL "$app_pid" 2>/dev/null
  fi
  if [ -n "$xvfb_pid" ]; then
    kill -TERM "$xvfb_pid" 2>/dev/null
    wait "$xvfb_pid" 2>/dev/null
  fi
  if [ -n "$log_out" ] && [ -f "$work/app.log" ]; then
    cp "$work/app.log" "$log_out" 2>/dev/null
  fi
  if [ "$keep_data" -eq 1 ]; then
    say "data and log kept in $work"
  else
    rm -rf "$work"
  fi
  exit "$status"
}
trap cleanup EXIT

fail_with_log() {
  say "$1"
  if [ -f "$work/app.log" ]; then
    say "--- last lines of the app output ---"
    tail -n 40 "$work/app.log" >&2
  fi
  exit 1
}

# A free display number.
if [ -n "${QUERYA_HEADLESS_DISPLAY:-}" ]; then
  num="${QUERYA_HEADLESS_DISPLAY#:}"
else
  num=99
  while [ -e "/tmp/.X${num}-lock" ] || [ -S "/tmp/.X11-unix/X${num}" ]; do
    num=$((num + 1))
    [ "$num" -lt 200 ] || die "no free X display between :99 and :199"
  done
fi
export DISPLAY=":${num}"

Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
for _ in $(seq 1 40); do
  [ -S "/tmp/.X11-unix/X${num}" ] && break
  kill -0 "$xvfb_pid" 2>/dev/null || { cat "$work/xvfb.log" >&2; die "Xvfb did not start"; }
  sleep 0.25
done
[ -S "/tmp/.X11-unix/X${num}" ] || die "Xvfb on $DISPLAY did not come up"
say "virtual display $DISPLAY"

# Portable mode keeps its data in {bundle}/QueryaData, so run a copy: the
# bundle that was built stays untouched and every run starts on an empty profile.
cp -a "$bundle" "$work/bundle" || die "could not copy $bundle"
export QUERYA_PORTABLE=1
export NO_AT_BRIDGE=1

# Own endpoint file, so that a second app on the machine (or a leftover one)
# can never be the one querya-mcp talks to.
export QUERYA_MCP_ENDPOINT="$work/mcp-endpoint.json"

runner=()
if command -v dbus-run-session >/dev/null 2>&1; then
  runner=(dbus-run-session --)
fi

start_app() {
  ${runner[@]+"${runner[@]}"} "$work/bundle/querya_desktop" >>"$work/app.log" 2>&1 &
  app_pid=$!
  say "started querya_desktop (pid $app_pid)"
}

stop_app() {
  [ -n "$app_pid" ] || return 0
  kill -TERM "$app_pid" 2>/dev/null
  for _ in $(seq 1 20); do
    kill -0 "$app_pid" 2>/dev/null || break
    sleep 0.5
  done
  kill -KILL "$app_pid" 2>/dev/null
  wait "$app_pid" 2>/dev/null
  app_pid=""
}

have_window_tool=0
if command -v xdotool >/dev/null 2>&1 || command -v xwininfo >/dev/null 2>&1; then
  have_window_tool=1
fi

window_up() {
  if command -v xdotool >/dev/null 2>&1; then
    xdotool search --onlyvisible --name '.' >/dev/null 2>&1
  else
    # A top-level window with a real size (nothing else maps one on a bare Xvfb).
    xwininfo -root -tree 2>/dev/null | grep -Eq '[0-9]{3,4}x[0-9]{3,4}\+'
  fi
}

wait_for_window() {
  local deadline=$((SECONDS + wait_s)) shown=0
  while [ "$SECONDS" -lt "$deadline" ]; do
    kill -0 "$app_pid" 2>/dev/null || fail_with_log "the app exited before showing a window"
    if [ "$have_window_tool" -eq 1 ]; then
      if window_up; then shown=1; break; fi
    fi
    sleep 1
  done
  if [ "$have_window_tool" -eq 1 ]; then
    [ "$shown" -eq 1 ] || fail_with_log "no window after ${wait_s}s"
    say "window is up"
  else
    say "no xdotool / xwininfo: only checking that the process stays alive"
  fi
}

start_app
wait_for_window

if [ -n "$seed_sql" ]; then
  # The first start created and migrated the profile database. Let it settle,
  # stop the app (it holds the file open), seed, and start again.
  sleep 2
  stop_app
  db="$(find "$work/bundle" -name querya.db -print -quit 2>/dev/null)"
  [ -n "$db" ] || fail_with_log "the profile database querya.db was not created"
  sqlite3 "$db" <"$seed_sql" || fail_with_log "could not apply $seed_sql to $db"
  say "seeded $(basename "$seed_sql") into $db"
  start_app
  wait_for_window
fi

end=$((SECONDS + keep_s))
while [ "$SECONDS" -lt "$end" ]; do
  kill -0 "$app_pid" 2>/dev/null || fail_with_log "the app exited after showing its window"
  sleep 0.5
done

if [ -n "$screenshot" ]; then
  mkdir -p "$(dirname "$screenshot")"
  if import -display "$DISPLAY" -window root "$screenshot" 2>"$work/import.log"; then
    say "screenshot: $screenshot"
  else
    cat "$work/import.log" >&2
    fail_with_log "could not take the screenshot"
  fi
fi

if [ -n "$run_cmd" ]; then
  export QUERYA_HEADLESS_DB
  QUERYA_HEADLESS_DB="$(find "$work/bundle" -name querya.db -print -quit 2>/dev/null)"
  export QUERYA_HEADLESS_DATA="$work/bundle/QueryaData"
  say "running: $run_cmd"
  if ! bash -c "$run_cmd"; then
    fail_with_log "--run command failed"
  fi
  kill -0 "$app_pid" 2>/dev/null || fail_with_log "the app died while the command ran"
fi

say "ok"
exit 0
