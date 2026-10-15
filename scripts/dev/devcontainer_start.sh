#!/usr/bin/env bash
# Runs every time the dev container starts (devcontainer.json: postStartCommand).
#
# 1. starts the database stack on the host's Docker daemon and waits until the
#    long-running services are healthy, with a clear status instead of hiding a
#    failure;
# 2. joins this container to the stack's network, so the service names resolve;
# 3. makes `localhost:<port>` work inside the container by forwarding the usual
#    ports to the services (the databases run next to the dev container, not in
#    it, so nothing listens on its loopback otherwise).
#
# It never fails the container start: a dev container without the databases is
# still useful for builds and tests.
set -u

compose_file="docker/docker-compose.yml"
project="querya-dev"
timeout="${QUERYA_STACK_TIMEOUT:-180}"

say() { printf '[querya-dev] %s\n' "$*"; }

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  say "Docker is not reachable from the container: the database stack is not started."
  say "Check that the host daemon runs, then: cd docker && docker compose up -d"
  exit 0
fi

say "starting the database stack ..."
if ! docker compose -f "$compose_file" up -d; then
  say "docker compose up failed (see the output above)."
  exit 0
fi

# Long-running services with a healthcheck; the seed jobs exit on their own.
services=(querya-postgres querya-mysql querya-redis querya-mongo querya-clickhouse)
deadline=$((SECONDS + timeout))
pending=("${services[@]}")
while [ "${#pending[@]}" -gt 0 ] && [ "$SECONDS" -lt "$deadline" ]; do
  next=()
  for name in "${pending[@]}"; do
    state="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || echo missing)"
    case "$state" in
      healthy | running) ;;
      *) next+=("$name") ;;
    esac
  done
  pending=("${next[@]}")
  [ "${#pending[@]}" -gt 0 ] && sleep 3
done

if [ "${#pending[@]}" -gt 0 ]; then
  say "not healthy after ${timeout}s: ${pending[*]} (docker compose -f $compose_file ps)"
else
  say "all databases are healthy."
fi

# Join the stack's network (a no-op when it is already joined, and not possible
# with host networking, where localhost already reaches the published ports).
docker network connect "${project}_default" "$(hostname)" >/dev/null 2>&1 || true

# localhost:<port> -> service:<port>. Skipped for a port something already
# listens on, and for a service name that does not resolve.
forward() {
  local port="$1" host="$2"
  if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    return 0
  fi
  if ! getent hosts "$host" >/dev/null 2>&1; then
    return 0
  fi
  command -v socat >/dev/null 2>&1 || return 0
  nohup socat "TCP-LISTEN:${port},bind=127.0.0.1,fork,reuseaddr" "TCP:${host}:${port}" \
    >/dev/null 2>&1 &
}

forward 5432 postgres
forward 3306 mysql
forward 6379 redis
forward 27017 mongo
forward 8123 clickhouse
forward 9000 clickhouse
# Profile `live-tests`: MySQL 8.0 with mysql_native_password, its own host port.
forward "${MYSQL_LIVE_PORT:-3307}" mysql-live

say "postgres :5432  mysql :3306  redis :6379  mongo :27017  clickhouse :8123/:9000 on localhost"
docker compose -f "$compose_file" ps --format 'table {{.Name}}\t{{.Status}}' 2>/dev/null || true
exit 0
