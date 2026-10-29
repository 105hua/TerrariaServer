#!/usr/bin/env bash
# Generates the server config from environment variables, picks or creates the
# world, then runs the server with its console attached to a named pipe so that
# `console <command>` works and SIGTERM saves the world before exiting.
set -euo pipefail

DATA_DIR=/data
WORLDS_DIR="$DATA_DIR/worlds"
CONFIG="$DATA_DIR/serverconfig.txt"
CONSOLE_PIPE=/tmp/terraria-console

WORLD_NAME="${WORLD_NAME:-world}"
WORLD_SIZE="${WORLD_SIZE:-medium}"
WORLD_DIFFICULTY="${WORLD_DIFFICULTY:-classic}"
WORLD_SEED="${WORLD_SEED:-}"
MAX_PLAYERS="${MAX_PLAYERS:-8}"
SERVER_PASSWORD="${SERVER_PASSWORD:-}"
MOTD="${MOTD:-}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

log() { echo "[entrypoint] $*"; }
die() { echo "[entrypoint] ERROR: $*" >&2; exit 1; }

case "${WORLD_SIZE,,}" in
    small)  autocreate=1 ;;
    medium) autocreate=2 ;;
    large)  autocreate=3 ;;
    *) die "WORLD_SIZE must be small, medium or large (got '$WORLD_SIZE')" ;;
esac

case "${WORLD_DIFFICULTY,,}" in
    classic) difficulty=0 ;;
    expert)  difficulty=1 ;;
    master)  difficulty=2 ;;
    journey) difficulty=3 ;;
    *) die "WORLD_DIFFICULTY must be classic, expert, master or journey (got '$WORLD_DIFFICULTY')" ;;
esac

[[ "$MAX_PLAYERS" =~ ^[0-9]+$ ]] && (( MAX_PLAYERS >= 1 && MAX_PLAYERS <= 255 )) \
    || die "MAX_PLAYERS must be a number from 1 to 255 (got '$MAX_PLAYERS')"

mkdir -p "$WORLDS_DIR"

# World selection: the named world, else the only world present, else create one.
world="$WORLDS_DIR/$WORLD_NAME.wld"
if [[ -f "$world" ]]; then
    log "Loading world '$WORLD_NAME'"
else
    shopt -s nullglob
    existing=("$WORLDS_DIR"/*.wld)
    shopt -u nullglob
    case "${#existing[@]}" in
        0)
            log "No world found - creating '$WORLD_NAME' (size: $WORLD_SIZE, difficulty: $WORLD_DIFFICULTY${WORLD_SEED:+, seed: $WORLD_SEED})"
            ;;
        1)
            world="${existing[0]}"
            log "No world named '$WORLD_NAME' - using the only world present: $(basename "$world")"
            ;;
        *)
            die "No world named '$WORLD_NAME' and several worlds exist. Set WORLD_NAME to one of: $(for w in "${existing[@]}"; do printf '%s ' "$(basename "$w" .wld)"; done)"
            ;;
    esac
fi

# Terraria cannot open worlds saved by a newer version, and the server just exits
# silently when asked to, so remember which version last ran each world.
server_version="$(cat /opt/terraria/VERSION)"
version_file="$world.server-version"
if [[ -f "$version_file" ]]; then
    world_version="$(tr -dc '0-9' < "$version_file")"
    if [[ -n "$world_version" ]] && (( world_version > server_version )); then
        die "$(basename "$world") was last run by Terraria $world_version and cannot be opened by $server_version. Set TERRARIA_VERSION=$world_version (or newer, or latest)."
    fi
fi
echo "$server_version" > "$version_file"

{
    echo "world=$world"
    echo "worldpath=$WORLDS_DIR"
    echo "worldname=$WORLD_NAME"
    echo "autocreate=$autocreate"
    echo "difficulty=$difficulty"
    [[ -n "$WORLD_SEED" ]] && echo "seed=$WORLD_SEED"
    echo "maxplayers=$MAX_PLAYERS"
    echo "port=7777"
    echo "password=$SERVER_PASSWORD"
    echo "motd=$MOTD"
    echo "banlist=$DATA_DIR/banlist.txt"
    echo "upnp=0"
} > "$CONFIG"

if [[ -n "$SERVER_PASSWORD" ]]; then log "Server password is set"; else log "No server password set"; fi
log "Terraria server version $server_version"

if command -v mono > /dev/null; then
    server=(mono --server --gc=sgen -O=all /opt/terraria/TerrariaServer.exe)
else
    server=(/opt/terraria/TerrariaServer.bin.x86_64)
fi

# Run the server as an unprivileged user that owns the data directory.
chown -R "$PUID:$PGID" "$DATA_DIR"

rm -f "$CONSOLE_PIPE"
mkfifo -m 600 "$CONSOLE_PIPE"
# Hold the pipe open read-write so the server never sees EOF between commands.
exec 3<> "$CONSOLE_PIPE"

cd /opt/terraria
HOME="$DATA_DIR" setpriv --reuid="$PUID" --regid="$PGID" --clear-groups \
    "${server[@]}" -config "$CONFIG" <&3 &
server_pid=$!

stop_server() {
    log "Stopping - saving world..."
    echo "exit" >&3
}
trap stop_server TERM INT

# `wait` returns early when a signal arrives; keep waiting until the server exits.
set +e
wait "$server_pid"
status=$?
while kill -0 "$server_pid" 2> /dev/null; do
    wait "$server_pid"
    status=$?
done
log "Server exited with status $status"
exit "$status"
