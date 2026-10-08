#!/usr/bin/env bash
# Prepares a Debian/Ubuntu machine (VM or LXC) as a host for self-hosted GitHub
# Actions runners that run the Querya test and analysis jobs (see
# docs/ci-runners.md). Safe to re-run: it skips what already exists.
#
# Run as root:
#   RUNNER_URL=https://github.com/QueryaHub/Querya-Desktop \
#   RUNNER_TOKEN=<registration token> \
#   RUNNER_COUNT=4 \
#   ./scripts/ci/setup-runner.sh
#
# The registration token comes from
#   gh api -X POST repos/QueryaHub/Querya-Desktop/actions/runners/registration-token --jq .token
# and expires after an hour.
#
# Optional: RUNNER_NAME_PREFIX (default querya-ci), RUNNER_LABELS (default
# querya-ci), RUNNER_USER (default runner), RUNNER_VERSION (default: latest).
set -euo pipefail

: "${RUNNER_URL:?set RUNNER_URL to the repository or organization URL}"
RUNNER_COUNT="${RUNNER_COUNT:-4}"
RUNNER_NAME_PREFIX="${RUNNER_NAME_PREFIX:-querya-ci}"
RUNNER_LABELS="${RUNNER_LABELS:-querya-ci}"
RUNNER_USER="${RUNNER_USER:-runner}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

echo "==> Packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# The native dependencies the hosted Ubuntu test job installs for the plugins,
# plus what the Flutter SDK itself needs (git, curl, unzip, xz, zip, GLU).
# libsqlite3-dev provides the unversioned libsqlite3.so that sqflite_common_ffi
# loads (the hosted Ubuntu image has it; a minimal container does not).
apt-get install -y -qq \
  ca-certificates curl git jq unzip xz-utils zip libglu1-mesa \
  libsecret-1-dev libsqlite3-dev

echo "==> User ${RUNNER_USER} (no sudo)"
if ! id "$RUNNER_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$RUNNER_USER"
fi

echo "==> Runner package"
if [[ -z "${RUNNER_VERSION:-}" ]]; then
  RUNNER_VERSION="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest \
    | jq -r .tag_name | sed 's/^v//')"
fi
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) RUNNER_ARCH=x64 ;;
  aarch64) RUNNER_ARCH=arm64 ;;
  *) echo "unsupported architecture: $ARCH" >&2; exit 1 ;;
esac
TARBALL="/var/cache/actions-runner-${RUNNER_VERSION}-${RUNNER_ARCH}.tar.gz"
if [[ ! -s "$TARBALL" ]]; then
  curl -fsSL -o "$TARBALL" \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
fi

for i in $(seq 1 "$RUNNER_COUNT"); do
  NAME="${RUNNER_NAME_PREFIX}-${i}"
  DIR="/home/${RUNNER_USER}/actions-runner-${i}"
  echo "==> ${NAME} (${DIR})"

  if [[ -f "$DIR/.runner" ]]; then
    echo "    already configured, skipping"
    continue
  fi
  : "${RUNNER_TOKEN:?set RUNNER_TOKEN (registration token) to add runners}"

  mkdir -p "$DIR"
  tar -xzf "$TARBALL" -C "$DIR"
  chown -R "$RUNNER_USER:$RUNNER_USER" "$DIR"

  # Keep the job environment predictable.
  printf 'LANG=C.UTF-8\nLC_ALL=C.UTF-8\n' > "$DIR/.env"
  chown "$RUNNER_USER:$RUNNER_USER" "$DIR/.env"

  (cd "$DIR" && runuser -u "$RUNNER_USER" -- ./config.sh --unattended --replace \
    --url "$RUNNER_URL" --token "$RUNNER_TOKEN" \
    --name "$NAME" --labels "$RUNNER_LABELS" --work _work)

  # systemd service running as the unprivileged user.
  (cd "$DIR" && ./svc.sh install "$RUNNER_USER" && ./svc.sh start)
done

echo "==> Done. Services:"
systemctl list-units --type=service --no-legend 'actions.runner.*' || true
