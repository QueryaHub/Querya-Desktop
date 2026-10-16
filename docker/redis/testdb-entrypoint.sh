#!/bin/sh
# Starts redis-server, seeds it once it answers, then waits for the server so
# that a stop signal reaches it and the container exits with its status.
set -eu

redis-server --save "" --appendonly no "$@" &
SERVER=$!
trap 'kill -TERM "$SERVER" 2>/dev/null' TERM INT

REDIS_HOST=127.0.0.1 REDIS_PORT=6379 sh /seed.sh

wait "$SERVER"
