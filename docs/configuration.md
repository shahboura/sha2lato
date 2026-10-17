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
| `AGENT_PACK` | `agents-opencode` | One workflow pack, version-pinnable: `agents-opencode[@x.y.z]`, `superpowers[@tag]`, or `none`. Bare = latest (re-resolved each start) ([usage.md](usage.md)) |
| `PONYTAIL` | `1` (on) | Minimal-code discipline plugin + `/ponytail` commands; set `0` to disable; spec override via `PONYTAIL_SPEC` ([usage.md](usage.md)) |
| `GRAPHIFY` | `1` (on) | Usage guide for the baked `graphify` CLI (repo → knowledge graph); set `0` to remove the guide |
| `GIT_USER_NAME` | `sha2lato agent` | identity for agent-made commits ([usage.md](usage.md) → Commits from the agent) |
| `GIT_USER_EMAIL` | `agent@sha2lato.local` | email for agent-made commits |
| `GIT_SIGN` | empty (off) | `1` = SSH-sign agent commits with `secrets/ssh/signing_key` |
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
  --build-arg GRAPHIFY_VERSION=0.9.90 \
  --build-arg GRAPHIFY_EXTRAS=leiden,mcp \
  -t my-agent agent/
```

Defaults: `KIMAKI_VERSION=latest`, `UIPRO_VERSION=latest` (the weekly rebuild refreshes them), `GRAPHIFY_VERSION=0.9.90`. `GRAPHIFY_EXTRAS` is empty by default (core graphify only — add `leiden` for community detection, `mcp` for the MCP server). Workflow packs are **not** build args — they're runtime config (`AGENT_PACK`), so changing pack or version never needs a rebuild.

## How changes apply

| Change | Apply with |
|---|---|
| any `secrets/.env.agent` value | `docker compose -f compose/docker-compose.yml up -d` (container recreates; data volume untouched) |
| `compose/.env` image (mode switch) | `./deploy/update.sh` — it detects the mode and either rebuilds (build-on-host) or pulls (pull-from-registry) |
| workflow pack switch or version pin | same command — no rebuild; the entrypoint converges at start (new versions fetch on first start with network, then cache on the volume) |

State — projects, sessions, model logins — always lives in the `sha2lato-agent-data` volume. Configuration changes never touch it.

## Pack-managed defaults

The fetched `agents-opencode` pack ships a blanket `external_directory: "deny"` rule, which would block this box's cross-directory flows (new-project clones, `kimaki project add`). So the entrypoint **normalizes the global `external_directory` rule to `"ask"` on every start, whatever `AGENT_PACK` is set to**: it drops the legacy v1 `external_directory` entry — and the deprecated `permission` object itself once that was its only key — removes any `external_directory` entries from the v2 `permissions` array, and appends the canonical rule last — `{"action": "external_directory", "resource": "*", "effect": "ask"}` (OpenCode evaluates rules in order; the last match wins). Other rules (v2 array entries, unrelated v1 keys) are left untouched. The global `external_directory` namespace is **box-owned**: entries you add there — including denies like `~/.ssh/*`, in either format — are removed on every start; rules that must survive belong under `agents.<id>.permissions` (agent rules are evaluated after global rules). In Discord, permission asks appear as approve buttons in the thread; **Accept Always** saves a project-scoped allow rule, and agent-level permissions are the per-agent override lever. Everything else in the volume-resident `opencode.json` (plugins, other rules) is left untouched — only the global `external_directory` rule is re-normalized each start.

`PONYTAIL=1` also merges the pinned ponytail plugin spec into that same `opencode.json` (`plugins` array) — it layers on top of any workflow pack; `PONYTAIL=0` strips it again. `GRAPHIFY=0` removes the graphify usage guide from the volume's skills directory (the CLI itself stays available).
