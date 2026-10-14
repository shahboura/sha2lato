# Deploy with Arcane

[Arcane](https://getarcane.app) is a Docker management UI (Compose projects, Git sync, shell access). This stack runs under it — with two recipes and a few rules, because Arcane keeps projects in its own directory and requires compose paths to stay **inside** the project folder.

## What stays the same

The **agent container is unchanged**: Discord `!` shell commands, the agent's own shell tool, DinD builds — Arcane only decides who runs `docker compose up`. Arcane's **Shell tab** (`containers:exec`) covers the host-CLI equivalents (`kimaki bot install-url`, `kimaki status`, `graphify …`).

## Recipe 1 — discovered project (keeps the repo checkout)

Mount Arcane's `PROJECTS_DIRECTORY` so the **parent of the repo checkout** is inside it (for example mount `/opt` with the checkout at `/opt/sha2lato`). Arcane scans nested folders, so `compose/docker-compose.yml` is discovered and all repo-relative paths (`../secrets/…`, `../agent`) resolve exactly as with a plain `docker compose`.

- Works in both [deployment modes](configuration.md#deployment-modes).
- Discovered projects can't be tagged in the UI; confirm Up/Redeploy once on first use.

## Recipe 2 — self-contained project (no checkout on the host)

Create a project in Arcane and paste this compose (registry mode). Put `KIMAKI_BOT_TOKEN`, `MACHINE_NAME`, `AGENT_PACK`, `PONYTAIL`, `GRAPHIFY` in the project's **Environment Configuration (.env)** editor. For git-over-SSH, create `secrets-ssh/` **on the host** (in Arcane's Projects Directory): `chmod 700` the folder, `chmod 600` the keys, plus `known_hosts` — SSH refuses group/world-readable keys, and the read-only mount means the container can't fix perms (the Workspace is fine only for `known_hosts`). Optional commit signing: add a dedicated `signing_key` the same way and set `GIT_SIGN=1` ([usage.md](usage.md) → Commits from the agent).

> ⚠️ **The token then lives in Arcane's store.** Arcane keeps project `.env` files in its own database — anyone with Arcane UI access can read them — and may include them in backups or exports. Treat that entry as a secret, **never** point a Push Git Sync or an export at it, and prefer **Recipe 1** (the token stays in the host's gitignored `secrets/.env.agent`). Same rule as [secrets.md](secrets.md): secrets never reach a repository.

```yaml
name: sha2lato
services:
  agent:
    image: ghcr.io/YOUR_USERNAME/sha2lato-agent:latest
    restart: unless-stopped
    env_file: .env
    environment:
      DOCKER_HOST: tcp://docker:2376
      DOCKER_TLS_VERIFY: "1"
      DOCKER_CERT_PATH: /certs/client
    volumes:
      - agent-data:/data
      - dind-certs:/certs:ro
      - ./secrets-ssh:/root/.ssh:ro
    healthcheck:
      test: ["CMD", "sh", "-c", "kimaki status --data-dir \"${KIMAKI_DATA_DIR:-/data}\""]
      interval: 60s
      timeout: 15s
      start_period: 60s
      retries: 3
  dind:
    image: docker:29-dind
    restart: unless-stopped
    privileged: true
    command: ["--host=tcp://0.0.0.0:2376", "--tlsverify"]
    environment:
      DOCKER_TLS_CERTDIR: /certs
      DOCKER_HOST: tcp://localhost:2376
      DOCKER_TLS_VERIFY: "1"
      DOCKER_CERT_PATH: /certs/client
    volumes:
      - dind-certs:/certs
      - dind-data:/var/lib/docker
volumes:
  agent-data:
    name: sha2lato-agent-data
  dind-certs:
    name: sha2lato-dind-certs
  dind-data:
    name: sha2lato-dind-data
```

## Rules for UI-managed installs

- **One owner per stack.** If Arcane manages it, do **not** set `DEPLOY_SSH_*` (the CI deploy job self-skips) and do **not** run `deploy/update.sh` — update with Arcane's **Redeploy** (pull + recreate) or **Auto Updates**. CI still builds and publishes images.
- **Explicit volume names** (`sha2lato-agent-data`, …) are set in both recipes: Arcane leaves explicitly-named volumes alone on project rename, so your data can't be copied or orphaned by a UI rename.
- **Paths must stay inside the project folder.** Arcane rejects compose path entries that point outside it; Recipe 2 exists precisely because the repo compose uses `../` paths.
- **Requirements:** a standard Docker daemon — privileged DinD does not work on rootless Docker or Podman; Compose ≥ 2.24 / Docker Engine 25+.
- **First start:** run `kimaki bot install-url` in the agent's Shell tab, authorize the bot, then restart the agent container.
- **Git Sync (Pull):** set **Compose File Path** to `compose/docker-compose.yml` (Recipe 1 layout) and enable **Sync Files**; secrets live in Arcane's `.env`/Workspace — synced files are read-only.
