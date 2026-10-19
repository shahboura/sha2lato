# Deploy with Docker Compose and management UIs

The base path is plain `docker compose` on the host — [hosting.md](hosting.md) sets it up and [configuration.md](configuration.md) covers every knob. This page covers the same stack under a **compose management UI**: [Arcane](https://getarcane.app), Dockge, Portainer, and similar all run the same compose file, so the two recipes and rules below apply to any of them. Arcane is the reference implementation — its concrete behavior is labeled **(Arcane)**.

## What stays the same

The **agent container is unchanged**: Discord `!` shell commands, the agent's own shell tool, DinD builds — the UI only decides who runs `docker compose up`. A UI **shell/exec tab** (Arcane: **Shell tab**, `containers:exec`) covers the host-CLI equivalents (`kimaki bot install-url`, `kimaki status`, `graphify …`).

## Recipe 1 — discovered project (keeps the repo checkout)

Mount the UI's projects directory (Arcane: `PROJECTS_DIRECTORY`) so the **parent of the repo checkout** is inside it (for example mount `/opt` with the checkout at `/opt/sha2lato`). Arcane scans nested folders, so `compose/docker-compose.yml` is discovered and all repo-relative paths (`../secrets/…`, `../agent`) resolve exactly as with a plain `docker compose`.

- Works in both [deployment modes](configuration.md#deployment-modes).
- Discovered projects can't be tagged in the UI (Arcane); confirm Up/Redeploy once on first use.

## Recipe 2 — self-contained project (no checkout on the host)

Create a project in the UI and paste this compose (registry mode). Put `KIMAKI_BOT_TOKEN`, `MACHINE_NAME`, `AGENT_PACK`, `PONYTAIL`, `GRAPHIFY` in the project's **environment editor** (Arcane: **Environment Configuration (.env)**) — workflow packs fetch at first start (network needed once), and `AGENT_PACK` takes an exact pin when you want one (`agents-opencode@3.1.2`, `superpowers@v7.0.0`). For git-over-SSH, create `secrets-ssh/` **on the host** (in Arcane's Projects Directory): `chmod 700` the folder, `chmod 600` the keys, plus `known_hosts` — SSH refuses group/world-readable keys, and the read-only mount means the container can't fix perms (Arcane's Workspace is fine only for `known_hosts`). Optional commit signing: add a dedicated `signing_key` the same way and set `GIT_SIGN=1` ([usage.md](usage.md) → Commits from the agent).

> ⚠️ **The token then lives in the UI's store.** Arcane keeps project `.env` files in its own database — anyone with Arcane UI access can read them — and may include them in backups or exports. Treat that entry as a secret, **never** point a Push Git Sync or an export at it, and prefer **Recipe 1** (the token stays in the host's gitignored `secrets/.env.agent`). Same rule as [secrets.md](secrets.md): secrets never reach a repository.

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
    networks:
      default:
        aliases:
          - docker
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

- **One owner per stack.** If a UI manages the stack, do **not** set `DEPLOY_SSH_*` (the CI deploy job self-skips) and do **not** run `deploy/update.sh` — update from the UI (Arcane: **Redeploy** — pull + recreate — or **Auto Updates**). CI still builds and publishes images.
- **Explicit volume names** (`sha2lato-agent-data`, …) are set in both recipes: Arcane leaves explicitly-named volumes alone on project rename, so your data can't be copied or orphaned by a UI rename.
- **Paths must stay inside the project folder.** Arcane rejects compose path entries that point outside it; Recipe 2 exists precisely because the repo compose uses `../` paths.
- **Requirements:** a standard Docker daemon — privileged DinD does not work on rootless Docker or Podman; Compose ≥ 2.24 / Docker Engine 25+.
- **First start:** run `kimaki bot install-url` in the agent's shell tab (Arcane: **Shell tab**), authorize the bot, then restart the agent container.
- **Git Sync (Pull, Arcane):** set **Compose File Path** to `compose/docker-compose.yml` (Recipe 1 layout) and enable **Sync Files**; secrets live in the UI's `.env`/Workspace — synced files are read-only.
