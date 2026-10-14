# Configuration

**Convention over configuration:** out of the box, the only value you *must* provide is your **Discord bot token**. Everything else has a default, every default has exactly one override point, and you never edit `compose/` or the `Dockerfile` for normal use.

## Easy mode: `./deploy/configure.sh`

On the host (after `bootstrap-host.sh`, or any checkout):

```bash
./deploy/configure.sh             # interactive: asks token, machine name, pack, worktrees
./deploy/configure.sh --show      # print current values
./deploy/configure.sh --non-interactive --token <t> --machine <m> --pack agents-opencode
```

It writes `secrets/.env.agent` + `compose/.env` (re-runs keep your current values as defaults), then just:

```bash
docker compose -f compose/docker-compose.yml up -d
```

## The two files

| File | From template | Holds | Committed |
|---|---|---|---|
| `secrets/.env.agent` | `secrets/.env.agent.example` | runtime config: bot token, pack, worktrees, optional keys | ❌ (chmod 600) |
| `compose/.env` | `compose/.env.example` | which image to run | ❌ |

Everything else in the repo is impersonal — fork-safe by design ([secrets.md](secrets.md)).

## Every knob

| Variable | Default | What it does |
|---|---|---|
| `KIMAKI_BOT_TOKEN` | **(required)** | your Discord bot token ([discord-bot.md](discord-bot.md)) |
| `MACHINE_NAME` | `sha2lato` | Discord category `Kimaki <name>` this machine owns |
| `AGENT_PACK` | `agents-opencode` | One workflow pack: `agents-opencode`, `superpowers`, or `none` ([usage.md](usage.md)) |
| `PONYTAIL` | `1` (on) | Minimal-code discipline plugin + `/ponytail` commands; set `0` to disable ([usage.md](usage.md)) |
| `GRAPHIFY` | `1` (on) | Usage guide for the baked `graphify` CLI (repo → knowledge graph); set `0` to remove the guide |
| `GIT_USER_NAME` | `sha2lato agent` | identity for agent-made commits ([usage.md](usage.md) → Commits from the agent) |
| `GIT_USER_EMAIL` | `agent@sha2lato.local` | email for agent-made commits |
| `GIT_SIGN` | empty (off) | `1` = SSH-sign agent commits with `secrets/ssh/signing_key` |
| `SUPERPOWERS_TAG` | `v7.0.0` | git tag to pin when `AGENT_PACK=superpowers` (≥ v6.4.1 needed on OpenCode v2) |
| `SUPERPOWERS_DISABLE_TELEMETRY` | `1` (off) | set `0` to allow the version-only telemetry ping |
| `KIMAKI_WORKTREES` | empty (off) | `1` = fresh git worktree per session — **leave empty when superpowers is active** |
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY` | empty | optional model keys; `/login` in Discord is the recommended path |
| `SHA2LATO_AGENT_IMAGE` | `sha2lato-agent:local` | selects the [deployment mode](#deployment-modes): local tag = build on host, any registry ref = pull |

Rarely-needed knobs:

| Variable | Where | What |
|---|---|---|
| `SHA2LATO_DIR` | host scripts | checkout location (default `/opt/sha2lato`) |
| `SSH_PORT` | `bootstrap-host.sh` | extra sshd port to keep open when enabling ufw |
| `DEPLOY_SSH_*`, `REGISTRY_*` | repo secrets | CI deploy + Forgejo registry ([ci-cd.md](ci-cd.md)) |

## Deployment modes

`SHA2LATO_AGENT_IMAGE` in `compose/.env` selects one of **two deployment modes**. Everything else — services, volumes, secrets — is identical.

| | `build-on-host` (default) | `pull-from-registry` |
|---|---|---|
| Value | `sha2lato-agent:local` | a registry ref, e.g. `ghcr.io/YOUR_USERNAME/sha2lato-agent:latest` |
| First start | `docker compose -f compose/docker-compose.yml up -d --build` | `docker compose -f compose/docker-compose.yml pull` then `up -d` |
| Updates | `./deploy/update.sh` rebuilds on the host | `./deploy/update.sh` pulls + recreates |
| Use when | first run, hacking on the image, no registry | the CI-published image: fast deploys, no build toolchain on the host, weekly CVE-fresh rebuilds |

- `deploy/update.sh` **detects the mode** from `compose/.env` and does the right thing; `--dry-run` prints the plan without executing.
- **Never run `up -d --build` in registry mode** — with both `image:` and `build:` set, it builds locally and tags over the registry ref instead of pulling.
- Switching modes = change the one line (`./deploy/configure.sh` asks), then `./deploy/update.sh`.

## Build-time (custom image)

The image lives in `agent/` and is parameterized for reproducible builds:

```bash
docker build \
  --build-arg KIMAKI_VERSION=1.0.0 \
  --build-arg UIPRO_VERSION=2.15.0 \
  --build-arg AGENTS_OPENCODE_VERSION=2.6.0 \
  --build-arg GRAPHIFY_VERSION=0.9.90 \
  --build-arg GRAPHIFY_EXTRAS=leiden,mcp \
  -t my-agent agent/
```

Defaults: `KIMAKI_VERSION=latest`, `UIPRO_VERSION=latest` (the weekly rebuild refreshes them), `AGENTS_OPENCODE_VERSION=2.6.0` (pinned — the pack is baked in), `GRAPHIFY_VERSION=0.9.90`. `GRAPHIFY_EXTRAS` is empty by default (core graphify only — add `leiden` for community detection, `mcp` for the MCP server).

## How changes apply

| Change | Apply with |
|---|---|
| any `secrets/.env.agent` value | `docker compose -f compose/docker-compose.yml up -d` (container recreates; data volume untouched) |
| `compose/.env` image (mode switch) | `./deploy/update.sh` — it detects the mode and either rebuilds (build-on-host) or pulls (pull-from-registry) |
| workflow pack switch | same command — no rebuild; the entrypoint converges the config on start |

State — projects, sessions, model logins — always lives in the `sha2lato-agent-data` volume. Configuration changes never touch it.

## Pack-managed defaults

When `AGENT_PACK=agents-opencode` installs, the entrypoint restores `permission.external_directory` to OpenCode's default (`"ask"`) — the pack's `"deny"` default would block this box's cross-directory flows (new-project clones, `kimaki project add`). In Discord, permission asks appear as approve buttons in the thread. `doom_loop` stays `"deny"` (blocks a tool repeated identically 3×). These live in the volume-resident `opencode.json`, which the pack installer never overwrites once set — edit it freely.

`PONYTAIL=1` also merges the pinned ponytail plugin spec into that same `opencode.json` (`plugins` array) — it layers on top of any workflow pack; `PONYTAIL=0` strips it again. `GRAPHIFY=0` removes the graphify usage guide from the volume's skills directory (the CLI itself stays available).
