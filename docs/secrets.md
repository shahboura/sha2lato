# Secrets & the fork guide

**Design rule: nothing personal ever touches this repo.** Everything sensitive lives in gitignored `*.env` files and `secrets/` directories, documented by committed `*.example` templates. Forkers copy the templates, fill in their own values, and never inherit anyone's credentials.

## Where each secret lives

| Secret | Lives in | Committed? | Consumed by |
|---|---|---|---|
| Discord bot token | `secrets/.env.agent` (`KIMAKI_BOT_TOKEN`) → persisted to `/data/kimaki.db` on first start | ❌ (template `.env.agent.example` ✅) | agent container |
| Model credentials | `/login` in Discord → OpenCode data on the volume; optional provider API keys in `secrets/.env.agent` | ❌ | agent container |
| Git SSH keys (for repos the agent works on) | `secrets/ssh/` (mounted read-only at `/root/.ssh`) | ❌ | agent container |
| Which agent image to run | `compose/.env` (`SHA2LATO_AGENT_IMAGE`) | ❌ (template `.env.example` ✅) | docker compose |
| CI deploy key | `DEPLOY_SSH_*` repository secrets on GitHub/Forgejo | ❌ (never in repo) | CI pipelines |
| Registry credentials | `REGISTRY_USERNAME`/`REGISTRY_TOKEN` repo secrets (Forgejo) / automatic `GITHUB_TOKEN` (GitHub) | ❌ | CI pipelines |
| age overlay (optional) | `secrets/age/*.age` + `secrets/age/recipient` (encrypted + public key — **safe to commit**), private key stays in `~/.config/sha2lato/age.key` | ✅ for `*.age` and `recipient` | you, on any machine |

> If you deploy with a UI like [Arcane](arcane.md) using its self-contained recipe, the bot token lives in that tool's project `.env` instead of `secrets/.env.agent`. The same rule applies: treat it as a secret, keep it out of any Git sync or export, and prefer the host-checkout recipe when you can.

## Runtime env files

```bash
cd /opt/sha2lato
cp secrets/.env.agent.example secrets/.env.agent
cp compose/.env.example compose/.env
```

**`secrets/.env.agent`** — required: `KIMAKI_BOT_TOKEN`. Optional: `MACHINE_NAME`, `KIMAKI_WORKTREES=1` (fresh git worktree per session), provider keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`) as an alternative to `/login`.

**`compose/.env`** — `SHA2LATO_AGENT_IMAGE`: leave the default for local builds, or point it at your registry image once CI publishes one:

```ini
SHA2LATO_AGENT_IMAGE=ghcr.io/YOUR_USERNAME/sha2lato-agent:latest
# or: SHA2LATO_AGENT_IMAGE=forgejo.example.com/YOUR_USERNAME/sha2lato-agent:latest
```

## Git SSH keys (for the agent's projects)

The agent clones and pushes over SSH. Give it a dedicated key — **do not reuse your personal key**.

```bash
cd /opt/sha2lato
mkdir -p secrets/ssh && chmod 700 secrets/ssh
ssh-keygen -t ed25519 -C "sha2lato-agent" -f secrets/ssh/id_ed25519 -N ""
chmod 600 secrets/ssh/id_ed25519
# pin the hosts so SSH never prompts inside the container
ssh-keyscan -t ed25519 <your-forgejo-host> github.com > secrets/ssh/known_hosts 2>/dev/null
```

Then add the **public** key (`secrets/ssh/id_ed25519.pub`) as a **deploy key** — separately on each host you use:

**Forgejo:** repo → *Settings → Deploy Keys → Add.* Enable write access if the agent should push (it usually should). Repeat per repository. *(For multiple repos, consider a machine/user key instead: Forgejo user → Settings → SSH keys.)*

**GitHub:** repo → *Settings → Deploy keys → Add deploy key.* Same write-access decision. *(For many repos: create a dedicated GitHub account or fine-grained PAT alternative — deploy keys are per-repo.)*

Verify from inside the container:

```bash
docker compose -f compose/docker-compose.yml exec agent sh -c 'ssh -T git@<your-forgejo-host> || true'
```

The `secrets/ssh/` directory is mounted read-only at `/root/.ssh`; the agent can use the keys but cannot modify them (that is intentional).

## CI deploy key

The pipelines deploy by SSH'ing to your host and running `deploy/update.sh`. Generate a dedicated key **on your workstation** and set:

| Secret (GitHub repo secrets / Forgejo repo secrets) | Value |
|---|---|
| `DEPLOY_SSH_HOST` | hostname or IP of the Docker host |
| `DEPLOY_SSH_USER` | SSH user (needs docker access — `root`, or a user in the `docker` group) |
| `DEPLOY_SSH_KEY` | **private** key contents (the whole `-----BEGIN…` block) |
| `DEPLOY_SSH_PORT` | optional, default `22` |

```bash
ssh-keygen -t ed25519 -C "sha2lato-ci-deploy" -f ~/.ssh/sha2lato_deploy -N ""
ssh-copy-id -i ~/.ssh/sha2lato_deploy.pub <user>@<host>
```

If the secrets are **not set**, the deploy jobs skip themselves with a notice — forks stay green without configuration.

## Optional: age overlay (encrypted backups you can commit)

Want your `.env` files backed up in the repo, safely? Encrypt them with [age](https://github.com/FiloSottile/age):

```bash
deploy/age.sh keygen      # creates ~/.config/sha2lato/age.key + secrets/age/recipient
deploy/age.sh encrypt     # secrets/.env.* → secrets/age/*.age  (committable)
deploy/age.sh decrypt     # restore on a new machine (bring your private key or AGE_KEYFILE env)
```

- The **private key never enters the repo** (`~/.config/sha2lato/age.key`, or wherever `AGE_KEYFILE` points). Back it up somewhere safe — it's the whole point.
- `secrets/age/*.age` and `secrets/age/recipient` are safe to commit (that's the design: forkers can encrypt *to* you, only you can decrypt).
- If you change your `.env`, re-run `deploy/age.sh encrypt` and commit the updated `.age` files.

## Never commit

Real `.env` files, `secrets/ssh/` contents, age private keys, or `data/`. The `.gitignore` blocks all of these — if `git status` ever shows one, something is wrong; stop and fix it before committing.

## Fork checklist

```bash
git clone <your-fork> && cd <your-fork>
cp secrets/.env.agent.example secrets/.env.agent   # paste your bot token
cp compose/.env.example compose/.env               # optional: point at your registry image
# optional CI: set DEPLOY_SSH_* (+ REGISTRY_* for Forgejo) repo secrets
```
