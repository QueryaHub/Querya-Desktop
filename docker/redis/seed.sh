#!/bin/sh
set -eu

HOST="${REDIS_HOST:-redis}"
PORT="${REDIS_PORT:-6379}"

echo "Waiting for Redis at ${HOST}:${PORT}..."
until redis-cli -h "$HOST" -p "$PORT" ping | grep -q PONG; do
  sleep 1
done

if redis-cli -h "$HOST" -p "$PORT" EXISTS querya:seed:marker | grep -q 1; then
  echo "Redis seed marker present — skipping."
  exit 0
fi

echo "Seeding Redis demo keys..."

redis-cli -h "$HOST" -p "$PORT" <<'EOF'
SET querya:demo:string "Hello from Querya Docker stack"
SET querya:config:version "1"
HSET querya:user:1 name "Alice Martin" email "alice@example.com" city "Berlin"
HSET querya:user:2 name "Bob Smith" email "bob@example.com" city "London"
RPUSH querya:tasks:open "Review PR" "Write docs" "Test Redis key editor"
SADD querya:tags:popular redis docker mongodb postgresql mysql
ZADD querya:leaderboard 980 "player_alpha" 875 "player_beta" 640 "player_gamma"
SET querya:seed:marker "1"
EOF

echo "Redis seed complete."
