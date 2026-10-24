# Usage — day 2 from your phone

The mental model is simple: **channels are projects, threads are sessions.**

- Send a message in a project channel → Kimaki starts a **thread** = one OpenCode session working in that project's directory.
- Return to any thread anytime (search, `/resume`) — or start a new one by sending a new message in the channel.
- Everything the agent does (reads, edits, test runs, docker builds) happens on **your** host, inside the agent container and its DinD sidecar.

## First steps in Discord

| Command | What it does |
|---|---|
| `/login` | Connect a model provider (Claude Pro/Max, ChatGPT, Gemini, API keys) — do this once |
| `/model` | Switch the model for a channel or session (or `/<name>-agent` shortcuts) |
| `/agent` | Switch the agent/system prompt |
| `/verbosity` | Tune how much the bot posts in a channel |
| `/session-id` | Show the session ID + command to open it in the OpenCode TUI (if you run one on the host) |

Long prompts are easier as **attachments**: tap `+` → “Send message as file”.

## Creating new projects (from Discord, no SSH needed)

The agent has the `kimaki` CLI on its PATH inside every session. To add a project, just ask:

> “Clone `git@your-forgejo-host:you/new-app.git` into `/data/projects/new-app` and add it as a project.”

The agent runs the clone + `kimaki project add /data/projects/new-app` — and a **new channel appears** in your server. Brand-new (not yet existing) projects work too:

> “Create a new project `scratch` in `/data/projects/scratch`, `git init` it, add a starter README, and add it as a project.”

Requirements: SSH access to the git host (see [secrets.md](secrets.md)); git present (it is, in the image).

## Everyday workflows

- **Queue work while the agent is busy** — end a message with `. queue` (or `/queue`); edit the Discord message later to update the queued text. Great from mobile: “run the full test suite and report back. queue”
- **Ask a side question without derailing** — end with `. btw` (or `/btw`): forks the context into a new thread while the main run continues.
- **Worktrees — isolated experiments** — `/new-worktree <name>` starts a session in a fresh git worktree (never touching your main checkout); `/merge-worktree` merges it back (rebase or squash). Make it automatic per channel with `kimaki channel worktrees on` (or `KIMAKI_WORKTREES=1` for all sessions).
- **Review diffs on your phone** — `/diff` posts a shareable web diff URL of the session's changes.
- **Tunnels — see your dev server from your phone** — ask the agent to run `kimaki tunnel -- <dev command>` (or `-p <port>`); it prints a public URL you can open anywhere. Keep a tunnel alive in a named background session and read its output later via `tuistory` — e.g. `tuistory launch "kimaki tunnel -- pnpm dev" -s myapp-dev`, then `tuistory read -s myapp-dev` to grab the URL.
- **Voice** — record a voice note (transcribed with your file tree for accuracy); or join the **Kimaki voice** channel and talk. `kimaki --voice <name>` once to change the voice.
- **Images & files** — attach screenshots/files to messages; the agent can also upload files back into the thread.
- **Shell commands** — prefix a message with `!` to run it raw in the project folder (e.g. `! git status`).
- **Routines — scheduled prompts** — ask for a cron-style routine (e.g. “every weekday at 8:00, summarize open PRs in this channel”) — great for morning digests from your phone.
- **Sessions sleep & wake** — long-idle sessions are cheap; resume whenever.

## Feature support (baked tools)

The box ships the full toolset — diff viewer, tunnels, background sessions, headless browser, and more — see [Baked-in tools & commands](commands.md) for the complete reference. Anything there is also runnable yourself with `! <cmd>` in a channel, or `docker compose -f compose/docker-compose.yml exec agent <cmd>` on the host.

## Access control

Only the server owner, members with **Manage Server**/**Administrator**, or members with a role named **`Kimaki`** can drive the bot. A role named **`no-kimaki`** blocks anyone (even admins). See [discord-bot.md](discord-bot.md).

## Docker-based projects

The agent has full `docker` (and `buildx`, `compose`) against the **DinD sidecar** — isolated from the host daemon. So it can `docker build`, `docker run`, spin up compose stacks, run test containers, and even multi-arch builds. Images live in the sidecar's own volume; if disk grows:

```bash
docker compose -f compose/docker-compose.yml exec dind docker image prune -af
```

**Ports & service URLs (DinD).** Services published to `127.0.0.1` inside a project's compose bind in the **sidecar's own network namespace** — unreachable from the agent. Publish to `0.0.0.0` and connect via `docker:<port>`:

```yaml
# docker-compose.override.yml (in the project)
services:
  postgres:
    ports:
      - "5432:5432"        # NOT "127.0.0.1:5432:5432"
```

Then `DATABASE_URL=postgres://user:pass@docker:5432/db`.

## Workflow pack + extras

One **workflow pack** (mutually exclusive) plus two **extras** (both on by default) — all configured in `secrets/.env.agent`:

| Setting | Default | What it adds | Best when |
|---|---|---|---|
| `AGENT_PACK=agents-opencode` | ✅ default | 10 agent personas (orchestrator, codebase, review, planner, docs, researcher, …), 16 commands, 27 skills — all languages. From npm; `@x.y.z` pins | You want a structured *delivery loop* with named specialists |
| `AGENT_PACK=superpowers` | — | The [Superpowers](https://github.com/obra/superpowers) methodology: brainstorm → spec → plan → subagent-driven execution → TDD → review. From git; `@v7.0.0` pins | You want plan-first discipline for autonomous work |
| `AGENT_PACK=none` | — | Nothing extra | Plain OpenCode + the baked design skills |
| `PONYTAIL=1` | ✅ on | [Ponytail](https://github.com/DietrichGebert/ponytail): minimal-code discipline — injects the "laziest senior dev" ruleset every turn, adds `/ponytail-review`, `/ponytail-audit`, `/ponytail-debt` | Always useful; pairs with either workflow pack |
| `GRAPHIFY=1` | ✅ on | The `graphify` CLI (baked into the image) plus a usage guide: code → queryable knowledge graph, queried instead of re-reading files | Large or unfamiliar repos, cross-cutting work |

```ini
# in secrets/.env.agent
AGENT_PACK=agents-opencode   # or: superpowers[@tag] | none; @x.y.z pins a version
PONYTAIL=1                   # 0 to disable
GRAPHIFY=1                   # 0 to disable
```

Then `docker compose -f compose/docker-compose.yml up -d`. Switching any of them later is the same one-line change + `up -d` — no rebuild; new pack versions fetch on first start (then cache on the volume).

**Discord synergy:** Kimaki exposes the packs natively — agents appear as `/<name>-agent` switches and commands as slash commands. Try `/plan-project`, `/execution-loop`, `/checkpoint` (agents-opencode), `/ponytail-review` (ponytail), or ask *“tell me about your superpowers”* (superpowers). For graphify, just say *“graph this repo first”* when a codebase is large or unfamiliar.

**Worktrees — one owner only:**

| Active pack | Worktree guidance |
|---|---|
| `agents-opencode` (or none) | Kimaki worktrees fully compatible — `KIMAKI_WORKTREES=1` or per-channel `kimaki channel worktrees on` |
| `superpowers` | **Leave `KIMAKI_WORKTREES` unset** (and channel worktrees off) — Superpowers manages git worktrees itself as part of its branch lifecycle; the entrypoint warns if both are set |

**Does this affect Kimaki?** No — Kimaki identifies sessions by its thread↔session mapping, not by filesystem layout, so sessions stay distinct no matter how git worktrees are managed. The only rule is worktree ownership (table above). With superpowers active, review changes through its branch/merge flow (`git log`, PR) rather than `/diff` on the main checkout — its work happens on its own branch.

**Details:**

- `agents-opencode` is fetched from npm on first start into `/data/opencode/npm` (on the volume — offline starts keep working afterwards) and installed into the global OpenCode config, all languages. Bare = npm latest, re-resolved every start; `agents-opencode@x.y.z` pins exactly. Verify in Discord: ask *“@orchestrator plan this”* or look for the slash commands.
- **Cross-directory access:** on every start, the entrypoint normalizes the global `external_directory` rule to `"ask"` in OpenCode v2's `permissions` array — the fetched agents-opencode pack ships a blanket `"deny"` that would silently block documented flows that write outside the session's project directory (cloning new projects, `kimaki project add`). The four everyday dirs (`/tmp/opencode` scratch, `/data/reports`, `/data/transcripts`, `/data/attachments`) are additionally **allow-listed on every start**, so routine cross-session work needs no button; everything else still asks. In Discord, permission asks appear as **approve buttons in the thread**: **Accept Always** saves a project-scoped allow rule, and agent-level permissions are the per-agent override lever.
- **Pack updates:** bare packs re-check for a newer version on every start; exact pins change only when you edit them. A version-tracked marker re-installs the pack files on the volume automatically.
- `superpowers` is fetched from git by OpenCode; bare = latest tag re-resolved each start (offline keeps the current spec), `superpowers@v7.0.0` pins exactly (needs ≥ v6.4.1 on OpenCode v2). Its version-only telemetry ping is off unless you set `SUPERPOWERS_DISABLE_TELEMETRY=0`.
- Switching packs removes the other pack's *plugin* entry automatically; to also remove `agents-opencode` files, run `docker compose -f compose/docker-compose.yml exec agent agents-opencode --global --uninstall` and change `AGENT_PACK` (otherwise it reinstalls on the next start).
- `ponytail` is an OpenCode **plugin** (pinned `@dietrichgebert/ponytail@5.3.2`, overridable with `PONYTAIL_SPEC`); OpenCode fetches it on first start. It layers on top of any workflow pack. `PONYTAIL=0` strips it from the config.
- `graphify` ships baked (pinned CLI in its own venv) with a short usage guide the agent loads when exploring large codebases: build with `graphify extract .` (add `--code-only` to stay fully offline), refresh with `graphify update .`, query with `graphify query` / `path` / `explain`. Graphs are per-checkout in `graphify-out/` (keep it out of git). `GRAPHIFY=0` removes only the guide — the CLI stays available.

## Commits from the agent

Agent-made commits use a baked default identity — `sha2lato agent <agent@sha2lato.local>` — so a first commit never fails with *"please tell me who you are"*. To commit as yourself, set `GIT_USER_NAME` / `GIT_USER_EMAIL` in `secrets/.env.agent`, or let the agent set a per-project `git config`.

**Signing (optional, SSH):** put a dedicated private key at `secrets/ssh/signing_key` on the host (see [secrets.md](secrets.md)), register its **public** half — GitHub: Settings → SSH and GPG keys → **Signing Key** (verification only); Forgejo: an account key, which *also* grants authentication rights, so use a dedicated forge account if that separation matters to you — then set `GIT_SIGN=1`. Commits are SSH-signed as the dedicated *agent* identity, separate from your personal signing key. Verify via the **Verified** badge on the host after pushing (`git log --show-signature` inside the box only shows a good-signature result once an allowed-signers file is configured).

## Multiple agent machines, one Discord server

Scale out by running the same stack on another host — each machine keeps its own projects, sessions, and model logins, and your phone sees them side by side in one server.

```mermaid
flowchart TB
    ds["One Discord server (yours)"]
    ds --> c1["category: Kimaki alpha"]
    ds --> c2["category: Kimaki workshop"]
    subgraph h1["Host 1 · bot 1 (MACHINE_NAME=alpha)"]
        c1 --> s1["channels owned by host 1<br/>projects, sessions, /data"]
    end
    subgraph h2["Host 2 · bot 2 (MACHINE_NAME=workshop)"]
        c2 --> s2["channels owned by host 2<br/>projects, sessions, /data"]
    end
```

**How routing works:** a channel belongs to the machine whose database registered it, and **other Kimaki bots ignore channels they don't own** — so multiple self-hosted bots coexist safely in the same server. Each bot only answers where its own channels live; the category (`Kimaki <machine>`) is its visible territory.

**Setup, per additional machine:**

1. Create a **new Discord application** for it (its own token) — same flow as [discord-bot.md](discord-bot.md).
2. On the new host: `bootstrap-host.sh` → `secrets/.env.agent` with the **new token** and a distinct `MACHINE_NAME` (e.g. `workshop`) → `docker compose -f compose/docker-compose.yml up -d`.
3. `docker compose … exec agent kimaki bot install-url` → invite **that bot** to the same server → `restart agent`.
4. Route work by machine: heavy builds on the beefier host, GPU work on the GPU box — projects are added per machine, so the channel list *is* your routing table.

> ⚠️ **One token = one machine.** Never run the same bot token on two hosts — both would log in as the same bot user and double-process every message.
> 💡 **Access control is server-wide** (the `Kimaki` / `no-kimaki` roles), so one role assignment covers all your machines.

## Updating the box

- `./deploy/update.sh` — detects the [deployment mode](configuration.md#deployment-modes) and rebuilds or pulls accordingly (or let CI do it on every push / weekly rebuild).
- Your sessions, logins, and projects live on the `sha2lato-agent-data` volume — updates never log you out. Projects stay in `/data/projects`.
- Diff links survive updates too: self-hosted critique keeps published diffs on its own `critique-data` volume (the instance `CRITIQUE_WORKER_URL` points at); links expire after 7 days.
