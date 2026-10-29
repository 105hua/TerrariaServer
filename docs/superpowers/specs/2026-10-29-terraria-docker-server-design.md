# Dockerized Vanilla Terraria Server — Design

Date: 2026-10-29

## Goal

A vanilla (no tModLoader/TShock) Terraria dedicated server that runs with a plain
`docker compose up -d` on any Docker host — Windows (Docker Desktop), macOS (Intel and
Apple Silicon) and Linux (amd64 and arm64). Defaults to the latest release, allows
pinning any version with a one-line change, and supports a server password.

## Decisions

- **Server files are fetched at image build time.** `TERRARIA_VERSION` (`latest` or a
  number such as `1449`) is a build arg. The image is tagged
  `terraria-vanilla:${TERRARIA_VERSION}`, so changing the pin produces a missing tag and a
  plain `docker compose up -d` builds it automatically. Updating `latest` requires
  `docker compose up -d --build`; the Dockerfile `ADD`s the version API so the cache is
  only invalidated when a new release appears.
- **Architecture is detected at build time** via `TARGETARCH`:
  - `amd64` — runs Re-Logic's bundled `TerrariaServer.bin.x86_64` unchanged.
  - `arm64` — runs `TerrariaServer.exe` under system Mono, with the bundled framework
    assemblies removed so Mono's own are used.
  - Anything else fails the build with a clear message.
- **`pull_policy: never`** — without it Compose first tries to pull
  `terraria-vanilla:<tag>` from Docker Hub, which would run someone else's image if one
  were ever published under that name. `never` still builds when the tag is missing.
- **Downgrade guard** — an older server given a newer world exits silently (status 0),
  which `restart: unless-stopped` turns into a quiet restart loop. The entrypoint records
  the version that last ran each world in `<world>.wld.server-version` and refuses to
  start an older version with an error naming the version required.
- **Sources:** `https://terraria.org/api/get/dedicated-servers-names` (latest) and
  `https://terraria.org/api/download/pc-dedicated-server/terraria-server-<ver>.zip`.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Download stage + per-arch runtime stages; non-root `terraria` user |
| `docker-compose.yml` | Build/run, port, `./data` volume, restart policy, stop grace; all settings defaulted so `.env` is optional |
| `entrypoint.sh` | Generate config, select/create world, run server, graceful shutdown |
| `console` | Helper to send a command to the running server |
| `.env.example` | Documented settings |
| `.gitignore` / `.gitattributes` | Ignore `.env` and `data/`; force LF on shell scripts |
| `README.md` | Usage |
| `test/smoke.sh` | End-to-end verification |

## Settings

- Build: `TERRARIA_VERSION` (default `latest`).
- Runtime: `SERVER_PASSWORD` (empty = none), `WORLD_NAME`, `WORLD_SIZE`
  (small/medium/large), `WORLD_DIFFICULTY` (classic/expert/master/journey), `WORLD_SEED`,
  `MAX_PLAYERS`, `SERVER_PORT` (host port), `MOTD`.
- `serverconfig.txt` is regenerated from env on every start; env is the source of truth.

## Data layout (`./data` → `/data`)

- `worlds/` — `.wld` files
- `serverconfig.txt` — generated
- `banlist.txt`

## World selection (every start)

1. `worlds/<WORLD_NAME>.wld` exists → load it.
2. Otherwise exactly one `.wld` in `worlds/` → load it, log which.
3. None → auto-create using size/difficulty/seed.
4. Several, none matching → exit with an error listing them.

## Console and shutdown

The server's stdin is a named pipe. `docker compose exec terraria console "<cmd>"` writes
to it. On SIGTERM the entrypoint sends `exit` so the world is saved before the container
stops (stop grace period 60s).

## Testing (`test/smoke.sh`)

- amd64: build, first start creates world, "Server started" reached, port reachable.
- Restart loads the same world (no regeneration).
- Password appears in generated config.
- `docker compose stop` saves the world (`.wld` mtime advances).
- Pinned version (`1449`) builds via plain `up` and runs that version.
- arm64 image builds and starts under emulation.
