# Agent-driven setup

**You are an AI agent.** Your user pointed you here to set up sha2lato. Read this whole page, then execute it top to bottom. [hosting.md](hosting.md), [discord-bot.md](discord-bot.md), [secrets.md](secrets.md) and [configuration.md](configuration.md) are the deep docs behind every step.

**Objective:** a Linux host running the sha2lato compose stack (agent + DinD sidecar), driven from the user's Discord server — channels are projects, threads are sessions. Tell the user what you're doing as you go, and stop at every **HUMAN** marker.

## Human-in-the-loop items

Request each one at the step noted; none of these can be done for the user.

| Item | At step | Why only the human |
|---|---|---|
| SSH + sudo access to the host | Preflight | You operate over their access — never invent credentials |
| A Discord server the user owns (or Manage Server on it) | 3 | Needed to create the app and invite the bot |
| Discord application + bot token | 3 | Created in the Developer Portal ([discord-bot.md](discord-bot.md), steps 0–1) |
| Browser authorization of the bot | 5 | The invite URL needs a logged-in Discord session |
| Choice of model provider via `/login` | 7 | A personal decision (Claude Pro/Max, ChatGPT, Gemini, API key) |

## Safety rules (non-negotiable)

- **The bot token goes to exactly one place:** `secrets/.env.agent` on the host. Never ask for it in chat, never echo it, never put it in a log, a commit, or a Discord message. Have the user run `./deploy/configure.sh` themselves (hidden prompt) or edit the file directly. If they paste the token to you anyway, treat it as leaked: reset it in the Developer Portal and write the new one to the file.
- **Never commit secrets.** `secrets/*.env`, `compose/.env`, `secrets/ssh/` and `data/` are gitignored; if `git status` shows one, stop and fix before doing anything else.
- **The stack publishes no ports** — the agent is outbound-only (Discord, registries). Do not add `ports:` mappings to the compose file.
- **The host is single-tenant:** the DinD sidecar is privileged, which is host-kernel-equivalent power ([hosting.md](hosting.md) → Security notes).

## Preflight

Ask the user for: the host address + SSH user, their fork/clone URL, and whether CI has already published an agent image — if yes, get its ref (→ registry mode, step 4). Then run these **on the host** (over SSH):

```bash
ssh -t <user>@<host>               # works, and gives you a TTY for sudo
docker version                     # client + server both print
docker compose version             # must be ≥ 2.24 (env_file.required)
sudo -v                            # succeeds (prompts for password over the TTY)
free -m && df -h                   # sanity: ≥ 2 GB RAM, a few GB free (sizing: hosting.md)
```

- Docker missing entirely, or a fresh cloud VM? Head to step 1 — `bootstrap-host.sh` installs Docker; VM specifics are in [hosting.md](hosting.md).

## Decisions — recommended defaults

You can proceed without asking as long as the user has not said otherwise:

| Decision | Default |
|---|---|
| Host | whatever the user provides (any Docker host; Azure VM flavor: [hosting.md](hosting.md) Path B) |
| Repo URL | the user's own fork/clone URL — always prefer it over upstream; upstream is fine for a try-run |
| Checkout dir | `/opt/sha2lato` (used below; `SHA2LATO_DIR` overrides) |
| Deployment mode | build-on-host; pull-from-registry only for an image the user already publishes ([configuration.md](configuration.md#deployment-modes)) |
| Workflow pack | `agents-opencode` (the built-in default) |
| Machine name | `sha2lato` — only ask when the user runs several machines against one server ([usage.md](usage.md#multiple-agent-machines-one-discord-server)) |

## Procedure

### 1. Get the repo on the host

Clone into a **user-writable** directory (`/opt` is often root-owned — step 2 places the canonical checkout for you):

```bash
git clone <user's fork/clone URL> ~/sha2lato
cd ~/sha2lato
```

A private fork over SSH? Clone over HTTPS instead (or add a key first) — the agent's own project keys come later ([secrets.md](secrets.md) → Git SSH keys).

**Verify:** `git remote -v` lists the URL the user gave you.

**On failure:** [hosting.md](hosting.md) → Path A (requirements + clone).

### 2. Bootstrap the host

```bash
sudo ./deploy/bootstrap-host.sh "<user's fork/clone URL>"
cd /opt/sha2lato
```

Passing the URL lets the script place the canonical checkout at `/opt/sha2lato` and chown it to your user. It also runs a full `apt-get upgrade` and enables unattended-upgrades — warn the user first on a host that is not fresh.

Then it installs Docker Engine + buildx/compose plugins from Docker's official apt repo, enables ufw (SSH only), and creates `secrets/.env.agent` + `compose/.env` from the templates. Idempotent — safe to re-run.

**Verify:** output ends with `[bootstrap] done. Next steps:`; `/opt/sha2lato` exists and is owned by the user; then `docker version` and `docker compose version` in a **fresh shell** (or `newgrp docker`) — bootstrap adds the user to the docker group, which applies to new sessions.

**On failure:** [troubleshooting.md → Host](troubleshooting.md#host).

### 3. HUMAN — Discord application + token

Hand the user [discord-bot.md](discord-bot.md) steps 0–1: create a server (dedicated to agents), create the application, **enable Message Content Intent**, Reset Token → copy.

The user then writes the token on the host, either way works:

```bash
cd /opt/sha2lato
./deploy/configure.sh        # HUMAN: paste the token at the hidden prompt (required on first run — Enter alone won't pass)
# or: $EDITOR secrets/.env.agent  →  KIMAKI_BOT_TOKEN=...
```

After the token is stored, the agent can set non-secret knobs the same way — the non-interactive form reuses it: `./deploy/configure.sh --machine sha2lato --pack agents-opencode` (add `--image <ref>` for registry mode).

**Verify:** `./deploy/configure.sh --show` prints `KIMAKI_BOT_TOKEN:  set`.

**On failure:** [discord-bot.md → Troubleshooting](discord-bot.md#troubleshooting).

### 4. Start the stack

```bash
docker compose -f compose/docker-compose.yml up -d --build
```

Build-on-host mode — the first build takes several minutes. Registry mode instead: put the user's image ref in `compose/.env` (or `./deploy/configure.sh --image <registry-ref>`), then `docker compose -f compose/docker-compose.yml pull && docker compose -f compose/docker-compose.yml up -d`.

**Verify:** `docker compose -f compose/docker-compose.yml ps` shows `agent` and `dind` as **Up (healthy)** — the agent healthcheck has a 60 s start period, so wait before judging.

**On failure:** [troubleshooting.md → Agent / bot](troubleshooting.md#agent--bot) and [→ Docker-in-Docker](troubleshooting.md#docker-in-docker-agent-builds).

### 5. HUMAN — authorize the bot

```bash
docker compose -f compose/docker-compose.yml exec agent kimaki bot install-url
```

Prints the bot's invite URL. The user opens it in a browser logged into Discord, picks their server, and clicks **Authorize**.

**Verify:** a URL prints. `no bot configured` means the token never reached the container — recheck step 3, then `docker compose -f compose/docker-compose.yml up -d`.

**On failure:** [troubleshooting.md → Agent / bot](troubleshooting.md#agent--bot).

### 6. Nudge + verify the category

If the category does not appear within a minute (the bot was invited after its first boot), give it a nudge:

```bash
docker compose -f compose/docker-compose.yml restart agent
```

**Verify:** the Discord server now shows a category **`Kimaki <MACHINE_NAME>`** with a `#kimaki` channel and an onboarding thread.

**On failure:** [troubleshooting.md → Agent / bot](troubleshooting.md#agent--bot).

### 7. HUMAN — connect a model

The user runs **`/login`** in any channel and connects Claude Pro/Max, ChatGPT, Gemini, or an API key. Then ask them to send a message in `#kimaki` (e.g. “reply with a one-line hello”) — it should open a thread and get an answer.

**Verify:** the agent replies in a thread. Auth/model errors despite a valid token? Check `secrets/.env.agent` for CRLF line endings ([troubleshooting.md → Agent / bot](troubleshooting.md#agent--bot)).

## After setup — hand over

- The user now drives the box from Discord: **channels are projects, threads are sessions**.
- Point them at [usage.md](usage.md) (day-2: new projects without SSH, queue, worktrees, tunnels) and [commands.md](commands.md) (every baked tool and slash command).
- Optional next steps when the user wants them: git SSH keys for the agent's projects ([secrets.md](secrets.md) → Git SSH keys); CI auto-deploys via `DEPLOY_SSH_*` repo secrets ([ci-cd.md](ci-cd.md); details in [secrets.md](secrets.md) → CI deploy key).

## Verification checklist

| Check | Command | Expected |
|---|---|---|
| Docker ready | `docker version` | client + server versions print |
| Compose new enough | `docker compose version` | ≥ 2.24 |
| Token configured | `./deploy/configure.sh --show` | `KIMAKI_BOT_TOKEN:  set` |
| Stack healthy | `docker compose -f compose/docker-compose.yml ps` | `agent` + `dind` → `Up (healthy)` |
| No published ports | `docker compose -f compose/docker-compose.yml ps` | ports column empty |
| Bot running | `docker compose -f compose/docker-compose.yml exec agent kimaki status` | reports the bot |
| Category exists | in Discord | `Kimaki <MACHINE_NAME>` + `#kimaki` |
| End to end | send a message in `#kimaki` | reply lands in a new thread |
