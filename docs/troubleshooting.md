# Troubleshooting

Start here:

```bash
cd /opt/sha2lato
docker compose -f compose/docker-compose.yml ps            # container health
docker compose -f compose/docker-compose.yml logs -f agent --tail 100
docker compose -f compose/docker-compose.yml exec agent kimaki status
```

## Agent / bot

| Symptom | Likely cause → fix |
|---|---|
| Agent container **restart-loops**; logs show `install_url` / gateway events | `KIMAKI_BOT_TOKEN` missing or malformed in `secrets/.env.agent` — the box fell back to Kimaki's shared-bot onboarding. Set the token → `up -d` |
| Bot **online but silent** in channels | Message Content Intent disabled in the Developer Portal, or the channel doesn't belong to this machine. Check [discord-bot.md](discord-bot.md) + Kimaki's `no-kimaki`/role rules |
| No `Kimaki <machine>` category after inviting the bot | Onboarding retries on next start: `docker compose -f compose/docker-compose.yml restart agent` |
| Sessions stop responding | `docker compose -f compose/docker-compose.yml exec agent opencode service restart` — Kimaki reconnects by itself |
| Need to restart just the bot | `docker compose -f compose/docker-compose.yml exec agent kimaki restart` (sessions keep running) |
| Where are the logs? | `… exec agent kimaki logs` → path (`/data/kimaki.log`); follow with `--follow`. The file resets on every bot start |
| Healthcheck reports **unhealthy** | `kimaki status` inside the container shows *why not running*; usually the same token issue as row 1 |
| `AGENT_PACK` / `PONYTAIL` / `GRAPHIFY` set but the feature isn't active | `docker compose -f compose/docker-compose.yml logs agent \| grep entrypoint` — the convergence lines print on every start. `agents-opencode`: delete the marker `/data/opencode/config/.agents-opencode-installed` and restart to reinstall. `ponytail`: OpenCode fetches the plugin on first start — needs network once. `graphify`: verify the CLI with `docker compose -f compose/docker-compose.yml exec agent graphify --help` |
| `graphify: command not found` inside the container | Should not happen (the CLI is baked into the image) — rebuild the image; the entrypoint never removes it, only the usage guide |

## Docker-in-Docker (agent builds)

| Symptom | Likely cause → fix |
|---|---|
| `Cannot connect to the Docker daemon` inside sessions | DinD sidecar down or certs stale: `docker compose -f compose/docker-compose.yml up -d dind` → re-run. If it persists, wipe the cert volume and recreate both: `down`, `docker volume rm sha2lato-dind-certs`, `up -d` (builds/images are in `sha2lato-dind-data`, unaffected) |
| Builds suddenly fail with TLS/cert errors | Same as above — the shared certs volume got corrupted; recreate it |
| Sidecar eats disk | Prune inside it: `docker compose -f compose/docker-compose.yml exec dind docker image prune -af` (DinD has its own image store) |
| QEMU/multi-arch builds hang | arm64 via QEMU is slow — expected. Prefer fewer platforms or a native arm64 host |

## Deploys (CI → host)

| Symptom | Likely cause → fix |
|---|---|
| Deploy job **skips with a notice** | `DEPLOY_SSH_*` secrets not set — expected on forks; set them to enable ([ci-cd.md](ci-cd.md)) |
| `git pull --ff-only` fails | Local changes on the host checkout: `git -C /opt/sha2lato status` → commit/stash/reset deliberately (local edits to `*.env` files are fine — they're gitignored) |
| SSH refused / host key mismatch | Key moved or host rebuilt: re-run `ssh-copy-id` and update `DEPLOY_SSH_KEY`; the workflow pins host keys via `ssh-keyscan` at deploy time |
| `docker compose pull` fails for the agent image | Image name wrong in `compose/.env` (registry path/owner), or the registry rejected anonymous pulls — make the package public or log in (`docker login`) on the host |

## Forgejo pipeline

| Symptom | Likely cause → fix |
|---|---|
| Job **queued forever** | The runner doesn't serve the `runs-on` label (`linux`). Check Site Administration → Runners; align the workflow |
| Preflight fails: “No Docker daemon in this job” | `container.valid_volumes` missing `/var/run/docker.sock` in the runner's `config.yaml` (then restart the runner), or the job's `container.volumes` request was removed ([ci-cd.md](ci-cd.md) → Forgejo runner requirements) |
| `mounting … /var/run/docker.sock` mount error | Double-mount: the runner has `docker_host: automount` **and** the workflow requests the socket — remove `container.volumes` from the workflows |
| Linters crash with weird `/repo` paths | You used `-v $PWD` mounts from inside a job container — paths resolve on the **host**. Pipe via stdin instead (see the existing lint steps) |
| `uses:` action can't be fetched | Instance `DEFAULT_ACTIONS_URL` points somewhere without `actions/*`/`docker/*` mirrors — adjust `app.ini` or use explicit action URLs |

## Git over SSH (agent → repos)

| Symptom | Likely cause → fix |
|---|---|
| `Host key verification failed` | `secrets/ssh/known_hosts` missing/stale — regenerate with `ssh-keyscan` ([secrets.md](secrets.md)) |
| `Permission denied (publickey)` | Public key not added as deploy key on that repo, or wrong key mounted. Test: `… exec agent ssh -T git@<host>` |
| Key perms warning | Host-side files must be `600`/`700`: `chmod 600 secrets/ssh/*`, `chmod 700 secrets/ssh` |

## Host

| Symptom | Likely cause → fix |
|---|---|
| Out of disk | `docker system prune -a` on the host (safe: removes unused images; volumes untouched), DinD prune, remove old project clones in `/data/projects` |
| Can't reach a service from outside | Expected — the stack publishes **no ports** (outbound-only design). Use tunnels ([usage.md](usage.md)) for dev servers |
| Auth failures to the host from CI after OS upgrade | `unattended-upgrades` may have restarted sshd — re-check `DEPLOY_SSH_*` and host firewall (ufw allows SSH) |
