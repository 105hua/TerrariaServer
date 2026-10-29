# Terraria Server (Docker)

A vanilla Terraria dedicated server that runs anywhere Docker does: Windows, macOS
(Intel and Apple Silicon) and Linux (amd64 and arm64). The official server is
downloaded from terraria.org when the image is built, and nothing is modded.

## Quick start

```sh
docker compose up -d
```

The first start builds the image, generates a world and starts the server on port
**7777**. Follow progress with `docker compose logs -f` and look for
`Server started`.

To change any settings, copy `.env.example` to `.env` and edit it. Changes take
effect on the next `docker compose up -d`.

## Settings

All settings live in `.env` and are documented in [`.env.example`](.env.example):

| Setting | Default | |
|---|---|---|
| `TERRARIA_VERSION` | `latest` | `latest` or a release number such as `1449` |
| `SERVER_PASSWORD` | *(none)* | Password players must enter to join |
| `SERVER_PORT` | `7777` | Port players connect to |
| `MAX_PLAYERS` | `8` | |
| `MOTD` | *(none)* | Message of the day |
| `WORLD_NAME` | `world` | World to load or create |
| `WORLD_SIZE` | `medium` | `small`, `medium` or `large` (new worlds only) |
| `WORLD_DIFFICULTY` | `classic` | `classic`, `expert`, `master` or `journey` (new worlds only) |
| `WORLD_SEED` | *(random)* | Seed for new worlds |
| `PUID` / `PGID` | `1000` | Owner of the files in `./data` (Linux hosts) |

## Changing version

Set `TERRARIA_VERSION` in `.env`, then run:

```sh
docker compose up -d
```

Each version is built into its own image tag (`terraria-vanilla:<version>`), so a
version you haven't used before is built automatically and switching back to one you
have is instant. Versions are the game's version number without the dots, e.g.
`1449` for 1.4.4.9 (`1.4.4.9` is also accepted). A version that doesn't exist fails
the build with an error saying so.

**Updating `latest`:** an existing `latest` image is reused until you rebuild it.
When a new Terraria release comes out, run:

```sh
docker compose up -d --build
```

Worlds can move to newer versions but **not back to older ones**. If you try, the
server stops with an error that names the version the world needs.

## Worlds

Worlds are stored in `./data/worlds/`. On each start the server:

1. loads `<WORLD_NAME>.wld` if it exists;
2. otherwise, if `data/worlds/` contains exactly one world, loads that;
3. otherwise, if there are no worlds, creates one from the `WORLD_*` settings.

To use an existing world, stop the server, copy the `.wld` file into `data/worlds/`
and start the server again. On a PC your own worlds are in
`Documents/My Games/Terraria/Worlds` (Windows),
`~/Library/Application Support/Terraria/Worlds` (macOS) or
`~/.local/share/Terraria/Worlds` (Linux). If you keep several worlds, set
`WORLD_NAME` to choose one.

`docker compose stop` (and `down`) saves the world before the container exits.

**Backups:** stop the server and copy the `data` folder.

## Server console

Send a command to the server:

```sh
docker compose exec terraria console say Hello everyone
docker compose exec terraria console playing
docker compose exec terraria console save
```

The output appears in `docker compose logs -f`. Run `console help` to see every
command.

## How it works

- `Dockerfile` downloads the requested version during the build. On **amd64** it
  runs Re-Logic's bundled server binary unchanged. On **arm64**, where that binary
  can't run, it runs the same `TerrariaServer.exe` under Mono. Docker picks the right
  one for the machine it's building on.
- `entrypoint.sh` writes `data/serverconfig.txt` from your settings on every start
  (edit `.env`, not that file), chooses the world and runs the server as a non-root
  user.

## Testing

```sh
test/smoke.sh                                  # this machine's architecture
SMOKE_PLATFORM=linux/arm64 SMOKE_TIMEOUT=2400 test/smoke.sh   # arm64 via emulation
```

The smoke test checks that a world is created, the password reaches the config, the
port accepts connections, console commands work, a stop saves the world, a restart
reuses the world, a pinned version builds and runs, and that opening a world with an
older version is refused. It uses its own port (17777), data directory and image
tags, so it is safe to run next to a real server.

Under emulation the arm64 server is several times slower (world creation alone takes
about 6 minutes). At that speed a client that connects and immediately disconnects
right after start-up can crash Terraria's network thread. This is a race in the game
itself. It wasn't reproducible on native amd64 with either the bundled runtime or Mono,
and the container restarts automatically if it ever happens.
