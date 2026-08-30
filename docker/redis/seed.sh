#!/bin/sh
set -eu

HOST="${REDIS_HOST:-redis}"
PORT="${REDIS_PORT:-6379}"

echo "Waiting for Redis at ${HOST}:${PORT}..."
until redis-cli -h "$HOST" -p "$PORT" ping | grep -q PONG; do
  sleep 1
done

echo "Flushing and re-seeding Redis keys..."
redis-cli -h "$HOST" -p "$PORT" FLUSHALL

redis-cli -h "$HOST" -p "$PORT" <<'REDIS_EOF'
SET querya:app:name "Querya Desktop"
SET querya:app:version "0.4.14"
SET querya:config:theme "dark"
SET querya:config:scale "1.0"
SET querya:config:refresh_rate_hz "120"
SET querya:metrics:uptime_seconds "86400"

HSET querya:user:1 id "1" name "Alice Martin" email "alice@example.com" city "Berlin" role "admin" is_active "true"
HSET querya:user:2 id "2" name "Bob Smith" email "bob@example.com" city "London" role "editor" is_active "true"
HSET querya:user:3 id "3" name "Carla Ruiz" email "carla@example.com" city "Madrid" role "viewer" is_active "false"
HSET querya:user:4 id "4" name "Daisuke Sato" email "daisuke@example.com" city "Tokyo" role "customer" is_active "true"

RPUSH querya:queue:tasks "Task 1: Generate monthly analytics" "Task 2: Sync marketplace plugins" "Task 3: Run CI regression tests" "Task 4: Clear expired sessions"
RPUSH querya:logs:recent "[INFO] 2026-08-26 10:00:00 - Server started" "[INFO] 2026-08-26 10:05:00 - Connection pool initialized" "[WARN] 2026-08-26 10:15:00 - High memory watermark reached"

SADD querya:tags:all "postgresql" "mysql" "sqlite" "redis" "mongodb" "clickhouse" "rust" "flutter" "datagrid" "sdui"
SADD querya:features:enabled "virtual_grid" "in_place_editing" "ast_filter" "quick_calc" "fluid_sidebar" "sandbox"

ZADD querya:leaderboard:points 15200 "alice_martin" 12400 "bob_smith" 9800 "carla_ruiz" 7500 "daisuke_sato" 4200 "elena_popova"
ZADD querya:metrics:cpu_usage 12.5 "host_01" 34.8 "host_02" 78.2 "host_03" 5.1 "host_04"

XADD querya:stream:events * event_type "user_login" user_id "1" ip "192.168.1.42"
XADD querya:stream:events * event_type "query_executed" db "postgresql" duration_ms "12"
XADD querya:stream:events * event_type "export_csv" rows "5000" duration_ms "45"

SET querya:seed:marker "1"
REDIS_EOF

echo "Redis seed complete."
