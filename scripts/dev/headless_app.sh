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
#   -h, --help          this text
#
# Exit codes: 0 the app started, showed a window and stayed up; 1 it died, or no
# window appeared in time; 2 usage error, missing bundle or missing tool.
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

runner=()
if command -v dbus-run-session >/dev/null 2>&1; then
  runner=(dbus-run-session --)
fi
${runner[@]+"${runner[@]}"} "$work/bundle/querya_desktop" >"$work/app.log" 2>&1 &
app_pid=$!
say "started querya_desktop (pid $app_pid)"

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

deadline=$((SECONDS + wait_s))
shown=0
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

say "ok"
exit 0
