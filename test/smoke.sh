#!/usr/bin/env bash
# End-to-end test of the Terraria server image. Uses its own compose project,
# port, image tag and data directory, so it won't touch a real server.
#
# Usage:
#   test/smoke.sh                                  # native architecture
#   SMOKE_PLATFORM=linux/arm64 test/smoke.sh       # e.g. arm64 under emulation
#
# Optional: SMOKE_TIMEOUT (seconds to wait for each server start, default 300),
#           SMOKE_PINNED_VERSION (older version to test pinning, default 1449).
set -euo pipefail

cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1   # stop Git Bash on Windows rewriting container paths

PLATFORM="${SMOKE_PLATFORM:-}"
TIMEOUT="${SMOKE_TIMEOUT:-300}"
PINNED_VERSION="${SMOKE_PINNED_VERSION:-1449}"
PORT=17777
PASSWORD='smoke pass!'

export COMPOSE_PROJECT_NAME=terraria-smoke
export SERVER_PORT="$PORT" WORLD_SIZE=small SERVER_PASSWORD="$PASSWORD"
export SMOKE_IMAGE="terraria-vanilla-smoke-$(echo "${PLATFORM:-native}" | tr '/' '-')"
if [[ -n "$PLATFORM" ]]; then export DOCKER_DEFAULT_PLATFORM="$PLATFORM"; fi

DATA_LATEST=./test/.data/latest
DATA_PINNED=./test/.data/pinned
CONTAINER=terraria-smoke-terraria-1

dc() { docker compose -f docker-compose.yml -f test/compose.smoke.yml "$@"; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; echo "--- container log (tail) ---" >&2; docker logs "$CONTAINER" 2>&1 | grep -v '%' | tail -20 >&2; exit 1; }
mtime() { stat -c %Y "$1" 2> /dev/null || stat -f %m "$1"; }

# grep -c reads the whole log; grep -q would exit early and SIGPIPE docker logs,
# which fails the pipeline under pipefail.
log_count() { docker logs "$CONTAINER" 2>&1 | grep -c -- "$1" || true; }
log_has() { [[ "$(log_count "$1")" -ge 1 ]]; }

# Waits until the container log contains PATTERN at least COUNT times.
wait_for_log() {
    local pattern="$1" count="${2:-1}" waited=0
    until [[ "$(log_count "$pattern")" -ge "$count" ]]; do
        (( waited += 2 ))
        (( waited <= TIMEOUT )) || fail "timed out after ${TIMEOUT}s waiting for '$pattern'"
        sleep 2
    done
}

# Deletes a data directory from inside a container, since the server's files are
# owned by the container user.
clean_data() {
    SMOKE_DATA_DIR="$1" dc run --rm --no-deps --entrypoint sh terraria -c 'rm -rf /data/* /data/.[!.]*' > /dev/null 2>&1 || true
    rm -rf "$1"
}

cleanup() {
    dc down --timeout 60 > /dev/null 2>&1 || true
}
trap cleanup EXIT

echo "== Smoke test (platform: ${PLATFORM:-native}) =="
cleanup
mkdir -p "$DATA_LATEST" "$DATA_PINNED"
clean_data "$DATA_LATEST"; clean_data "$DATA_PINNED"
mkdir -p "$DATA_LATEST" "$DATA_PINNED"

# --- Latest version: first start creates a world -----------------------------
export SMOKE_DATA_DIR="$DATA_LATEST" TERRARIA_VERSION=latest
dc up -d --build
wait_for_log "Server started"
log_has "No world found - creating" || fail "world was not auto-created"
[[ -f "$DATA_LATEST/worlds/world.wld" ]] || fail "world.wld not written to the data directory"
pass "latest version starts and auto-creates a world"

grep -qxF "password=$PASSWORD" "$DATA_LATEST/serverconfig.txt" || fail "password missing from serverconfig.txt"
pass "server password written to config"

# Terraria itself can crash if a client connects and drops in the first moments
# after "Server started" - only reachable when the server is very slow, e.g. arm64
# under emulation. Give it time to settle so the test doesn't trip over that.
sleep 15
(echo > "/dev/tcp/127.0.0.1/$PORT") 2> /dev/null || fail "port $PORT is not accepting connections"
pass "port $PORT accepts connections"

dc exec -T terraria console say smoke-console-check
wait_for_log "smoke-console-check"
pass "console command reaches the server"

sleep 5
[[ "$(log_count "FATAL")" -eq 0 ]] || fail "the server crashed"
pass "server is still running after connections and commands"

# --- Graceful stop saves the world --------------------------------------------
before="$(mtime "$DATA_LATEST/worlds/world.wld")"
sleep 2
dc stop
after="$(mtime "$DATA_LATEST/worlds/world.wld")"
(( after > before )) || fail "world was not saved on stop (mtime $before -> $after)"
[[ "$(docker inspect -f '{{.State.ExitCode}}' "$CONTAINER")" == 0 ]] || fail "server did not exit cleanly"
pass "docker compose stop saves the world and exits cleanly"

# --- Restart reuses the existing world ----------------------------------------
dc up -d
wait_for_log "Server started" 2
[[ "$(log_count "No world found")" -eq 1 ]] || fail "world was regenerated on restart"
log_has "Loading world 'world'" || fail "existing world not loaded"
pass "restart loads the existing world"
dc down --timeout 60

# --- Pinned version is built by a plain `up` ----------------------------------
export SMOKE_DATA_DIR="$DATA_PINNED" TERRARIA_VERSION="$PINNED_VERSION"
docker image rm "$SMOKE_IMAGE:$PINNED_VERSION" > /dev/null 2>&1 || true
dc up -d
wait_for_log "Server started"
log_has "Terraria server version $PINNED_VERSION" || fail "pinned version $PINNED_VERSION not running"
pass "TERRARIA_VERSION=$PINNED_VERSION builds automatically and runs"
dc down --timeout 60

# --- Downgrading a world is refused with a clear error ------------------------
export SMOKE_DATA_DIR="$DATA_LATEST"
dc up -d
wait_for_log "cannot be opened by $PINNED_VERSION"
pass "older version refuses a newer world with a clear error"
dc down --timeout 60

clean_data "$DATA_LATEST"; clean_data "$DATA_PINNED"
echo "== All smoke tests passed (platform: ${PLATFORM:-native}) =="
