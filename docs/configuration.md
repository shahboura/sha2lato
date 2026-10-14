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
| `AGENT_PACK` | empty (none) | `agents-opencode` **or** `superpowers` — one workflow pack at a time ([usage.md](usage.md)) |
| `SUPERPOWERS_TAG` | `v7.0.0` | git tag to pin when `AGENT_PACK=superpowers` (≥ v6.4.1 needed on OpenCode v2) |
| `SUPERPOWERS_DISABLE_TELEMETRY` | `1` (off) | set `0` to allow the version-only telemetry ping |
| `KIMAKI_WORKTREES` | empty (off) | `1` = fresh git worktree per session — **leave empty when superpowers is active** |
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY` | empty | optional model keys; `/login` in Discord is the recommended path |
| `SHA2LATO_AGENT_IMAGE` | `sha2lato-agent:local` | image to run: local build tag, or your registry image ([ci-cd.md](ci-cd.md)) |

Rarely-needed knobs:

| Variable | Where | What |
|---|---|---|
| `SHA2LATO_DIR` | host scripts | checkout location (default `/opt/sha2lato`) |
| `SSH_PORT` | `bootstrap-host.sh` | extra sshd port to keep open when enabling ufw |
| `DEPLOY_SSH_*`, `REGISTRY_*` | repo secrets | CI deploy + Forgejo registry ([ci-cd.md](ci-cd.md)) |

## Build-time (custom image)

The image lives in `agent/` and is parameterized for reproducible builds:

```bash
docker build \
  --build-arg KIMAKI_VERSION=1.0.0 \
  --build-arg UIPRO_VERSION=2.15.0 \
  --build-arg AGENTS_OPENCODE_VERSION=2.6.0 \
  -t my-agent agent/
```

Defaults: `KIMAKI_VERSION=latest`, `UIPRO_VERSION=latest` (the weekly rebuild refreshes them), `AGENTS_OPENCODE_VERSION=2.6.0` (pinned — the pack is baked in).

## How changes apply

| Change | Apply with |
|---|---|
| any `secrets/.env.agent` value | `docker compose -f compose/docker-compose.yml up -d` (container recreates; data volume untouched) |
| `compose/.env` image | same command (after `docker compose pull` in registry mode) |
| workflow pack switch | same command — no rebuild; the entrypoint converges the config on start |

State — projects, sessions, model logins — always lives in the `agent-data` volume. Configuration changes never touch it.

## Pack-managed defaults

When `AGENT_PACK=agents-opencode` installs, the entrypoint restores `permission.external_directory` to OpenCode's default (`"ask"`) — the pack's `"deny"` default would block this box's cross-directory flows (new-project clones, `kimaki project add`). In Discord, permission asks appear as approve buttons in the thread. `doom_loop` stays `"deny"` (blocks a tool repeated identically 3×). These live in the volume-resident `opencode.json`, which the pack installer never overwrites once set — edit it freely.
