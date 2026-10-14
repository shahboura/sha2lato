# Hosting

Two first-class paths. Both end at the same place: a Linux host running the compose stack, driven from Discord.

| | Path A — Bring your own Docker host | Path B — Azure VM |
|---|---|---|
| You have | any Linux box with Docker + SSH (VPS, home server, NAS with Docker) | nothing yet; want turnkey cloud |
| Setup | run `deploy/bootstrap-host.sh` | create VM (below) → same script |
| Networking | works behind NAT — the agent is **outbound-only** (Discord, registries); only SSH needs to be reachable by CI | NSG: allow SSH only |
| Cost | what you already pay | ~a few $/month (B2s-class) |

Either way you need: **SSH access**, **Docker Engine**, and (recommended) a **firewall**.

---

## Path A — Bring your own Docker host

**Requirements:** Linux (Ubuntu/Debian gets the most automation), Docker Engine 25+ (the compose file uses `env_file.required`, which needs Compose ≥ 2.24), `git`, and SSH access for CI deploys.

```bash
# on the host, once
git clone <your-fork-url> /opt/sha2lato     # or let the script do it
cd /opt/sha2lato
sudo ./deploy/bootstrap-host.sh            # installs Docker, ufw, unattended-upgrades; clones if needed
```

The bootstrap script is idempotent — safe to re-run. It:
1. Installs Docker Engine + buildx + compose plugins from **Docker's official apt repo**
2. Enables **ufw** with SSH-only inbound (see [Firewall](#firewall-and-ufw))
3. Enables **unattended-upgrades** (OS-level CVE hygiene)
4. Clones (or updates) the repo into `/opt/sha2lato` and creates `secrets/.env.agent` + `compose/.env` from the templates
5. Adds your sudo user to the `docker` group

Then follow the next steps it prints: fill in `secrets/.env.agent` ([discord-bot.md](discord-bot.md)), add git SSH keys ([secrets.md](secrets.md)), and start:

```bash
cd /opt/sha2lato
# build-on-host mode (the default). Using the CI-published image instead?
# see configuration.md → Deployment modes.
docker compose -f compose/docker-compose.yml up -d --build
```

### Updates

`deploy/update.sh` detects the [deployment mode](configuration.md#deployment-modes) from `compose/.env`, then either rebuilds on the host or pulls the registry image and recreates the stack. (`--dry-run` prints the plan.)

- **CI mode (recommended):** set your `DEPLOY_SSH_*` repo secrets and every push to `main` (plus the weekly rebuild) deploys automatically.
- **Manual:** `cd /opt/sha2lato && ./deploy/update.sh`
- The host's git `origin` is the pull source. Point it at whichever remote is canonical for you (Forgejo or GitHub):
  `git -C /opt/sha2lato remote set-url origin <url>`

---

## Path B — Azure VM (turnkey flavor)

Create an Ubuntu 24.04 LTS VM (any `Standard_B2s`/`B2ms`-class size; arm64 SKUs work too — the image is multi-arch):

1. **Create the VM.** SSH in with the key Azure generated.
2. **NSG (network security group):** allow inbound **SSH (22) only** — ideally restricted to your IP + your CI egress if you know it. Nothing else needs to be open: the agent makes outbound connections only.
3. **Bootstrap:**

```bash
sudo apt-get update && sudo apt-get install -y git
git clone <your-fork-url> /opt/sha2lato
cd /opt/sha2lato
sudo ./deploy/bootstrap-host.sh
```

4. Continue exactly like Path A (fill env files → `up -d`).

**Azure-specific notes**

- Ubuntu cloud images ship with `ufw` installed but **inactive**; the bootstrap script enables it with SSH-only rules. If you rely on the NSG alone, you can remove the two ufw lines from the script — both layers are valid, choose one.
- Azure requires the VM's SSH key at creation; add that same public key (or a dedicated deploy key) to the host's `~/.ssh/authorized_keys` for your CI user.

---

## Firewall and ufw

**ufw = Uncomplicated Firewall** — the standard Ubuntu/Debian front-end for Linux firewalls. `bootstrap-host.sh` runs:

```bash
ufw allow OpenSSH     # keep SSH reachable (you + CI deploys)
ufw --force enable    # default-deny everything else inbound
```

**Why this is enough:** the agent box needs **no inbound ports**. Kimaki connects *out* to Discord; Docker builds happen inside the stack; the kimaki lock port and DinD daemon are container-internal. The only inbound service is SSH.

**One caveat, worth knowing:** Docker manages its own iptables rules and **published container ports bypass ufw**. This stack publishes **zero ports**, so there is nothing to bypass — but if you later add a service with a `ports:` mapping, remember it will be reachable regardless of ufw, and firewall it at the NSG/cloud level instead.

**Non-standard SSH ports:** `bootstrap-host.sh` reads your sshd config (`sshd -T`, run as root) and keeps every listed port open alongside the standard `OpenSSH` rule — so enabling ufw cannot lock you out, even when run via `sudo` (which strips session environment variables). You can also pass an extra port explicitly: `sudo SSH_PORT=2222 ./deploy/bootstrap-host.sh`.

---

## Sizing

| Workload | Suggested |
|---|---|
| Agent + DinD idling, light sessions | 2 GB RAM / 2 vCPU — workable |
| Comfortable daily driving, docker builds by the agent | 4 GB RAM / 2 vCPU |
| Heavy projects / many parallel sessions | 8 GB — plenty |

Notes:

- CI builds do **not** run on this host (GitHub hosted runners / your Forgejo runner do that), so the box only needs to run the agent + DinD.
- Disk: count on ~5–10 GB base + whatever your projects and images use. DinD keeps its own image store (the `dind-data` volume) — `docker compose ... exec dind docker image prune -af` occasionally if it grows.
- arm64 hosts (e.g. Azure Dpsv5/Dplsv5) are fully supported — the published images are multi-arch, and arm64 builds inside DinD run natively.

---

## Day-2 operations

```bash
cd /opt/sha2lato

# status / logs
docker compose -f compose/docker-compose.yml ps
docker compose -f compose/docker-compose.yml logs -f agent

# update to the latest published image
./deploy/update.sh

# open a shell inside the agent (e.g. to add an SSH key or inspect projects)
docker compose -f compose/docker-compose.yml exec agent bash
```

For "something is wrong" moments, see [troubleshooting.md](troubleshooting.md).
