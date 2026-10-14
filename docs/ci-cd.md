# CI/CD

Two pipelines, one goal: build the agent image for **linux/amd64 + linux/arm64**, publish it to a registry, and deploy it to your host over SSH. Neither pipeline needs a runner you don't already have.

| Pipeline | File | Runs on | Publishes to | Deploys |
|---|---|---|---|---|
| GitHub | `.github/workflows/` | GitHub's free hosted runners (public repo) | GHCR (`ghcr.io/<owner>/sha2lato-agent`) | SSH → `deploy/update.sh` |
| Forgejo | `.forgejo/workflows/ci.yml` | **your existing act_runner** | your Forgejo container registry | SSH → `deploy/update.sh` |

Both are mirrors of each other: lint → build (multi-arch) → deploy, plus a **weekly rebuild** (Monday 03:17 UTC) that republishes `:latest` with fresh base layers and deploys it, keeping hosts CVE-fresh without code changes.

## GitHub pipeline

- **`ci.yml`** — on push to `main`, version tags (`v*`), manual dispatch: runs `lint` (shellcheck + hadolint + actionlint, in pinned containers), calls the reusable **`build.yml`** (QEMU + buildx → GHCR; tags: `latest`, `sha-…`, semver), then calls **`deploy.yml`**.
- **`deploy.yml`** — reusable, **self-skipping**: if `DEPLOY_SSH_HOST` isn't configured it logs a notice and succeeds (forks stay green). Serialized with `concurrency: deploy`.
- **`rebuild.yml`** — the weekly cron: build + deploy, no code change required.
- **`renovate.json`** — Renovate opens PRs for base-image and action updates (`pinDigests` on).

**Secrets to set** (repo → Settings → Secrets and variables → Actions): `DEPLOY_SSH_HOST`, `DEPLOY_SSH_USER`, `DEPLOY_SSH_KEY`, optionally `DEPLOY_SSH_PORT`. `GITHUB_TOKEN` is automatic. See [secrets.md](secrets.md).

## Forgejo pipeline

- On push to `main`, version tags, the weekly cron, and manual dispatch: `lint` → `build` (multi-arch default) → `deploy`. The deploy step has the same self-skipping behavior.
- **Registry:** your Forgejo instance's built-in container registry. Set the two `forgejo.example.com` placeholders in the workflow to your host, and add repo secrets `REGISTRY_USERNAME` + `REGISTRY_TOKEN` (a Forgejo token with package write access).
- Override platforms on manual dispatch via the `platforms` input (e.g. `linux/amd64` to skip the heavy QEMU arm64 leg).

### Forgejo runner requirements

The pipeline runs on **your** act_runner, so unlike GitHub's hosted runners, the environment must be set up. Reference setup (exactly what this repo's workflow expects):

1. **A label the workflow targets.** The workflow uses `runs-on: linux`. Check your runner's labels in Forgejo → *Site Administration → Runners* (or repo *Settings → Actions → Runners*) and change `runs-on:` to match if needed.
2. **Socket whitelist for job containers.** In the runner's `config.yaml`:
   ```yaml
   container:
     valid_volumes:
       - /var/run/docker.sock
   ```
   The workflow then requests the socket per job (`container.volumes`), so only jobs that need Docker get it.
3. **A job image with the tools, all from official sources.** The workflow pins `node:24-bookworm` (Docker Official, by digest) and installs Docker CLI + buildx from Docker's official apt repo in a ~30 s setup step. Everything else (node, git, bash, ssh, curl) ships in the image.

**Alternative job image:** `catthehacker/ubuntu:act-latest` (digest in the workflow header comment history) is the community-standard act image — used by nektos/act itself — and bundles docker CLI + buildx + node + tooling, so the setup step can be dropped. Trade-off: a single-maintainer community image (MIT, 5M+ pulls) vs first-party sources. Either works; pick your trust model.

**Alternative socket strategies** (from Forgejo's official docs):

- `container.docker_host: 'automount'` in the runner config — mounts the host socket into *every* job container automatically. If you switch to this, **remove `container.volumes` from the workflows** (mounting the same path twice is an error).
- A `docker:dind` **service** per job (see Forgejo's "Utilizing Docker within Actions" guide) — best isolation, more setup.
- Worst case, per the Forgejo docs: mounting the host socket into jobs gives jobs access to **all host containers** — acceptable for a personal build runner with trusted workflows; for multi-tenant setups prefer dind.

**Notes:**

- With the socket-request approach, a job **must not** use `-v $PWD:…` mounts for tools like linters — a container created through the host socket resolves paths against the **host** filesystem, where the job workspace doesn't exist. This repo's lint steps pipe files via **stdin** instead (see any `lint` step). Same pattern works if you write your own workflows.
- Forgejo Runner **never updates already-downloaded images** — another reason everything here is pinned by digest.
- If `uses:` actions fail to resolve, check your instance's `DEFAULT_ACTIONS_URL` (`app.ini`): the default (`data.forgejo.org`) hosts the `actions/*` and `docker/*` mirrors these workflows use.
- Prefer a quick self-test? Run the **`runner-check`** workflow (manual dispatch) — it executes the exact Docker requirements of the real pipeline.

## Deploys (both pipelines)

The deploy step SSHes to your host and runs `deploy/update.sh`:

```
git pull --ff-only        # the host's checkout (default /opt/sha2lato)
# mode-aware — the script detects it from compose/.env:
#   build-on-host      → docker compose -f compose/docker-compose.yml build
#   pull-from-registry → docker compose -f compose/docker-compose.yml pull
docker compose -f compose/docker-compose.yml up -d --remove-orphans
docker image prune -f
```

- The host's git **`origin`** is the pull source — point it at whichever remote you treat as canonical (Forgejo or GitHub). Both pipelines can deploy the same host; deploys are serialized per workflow.
- **Modes:** `deploy/update.sh` reads `compose/.env` and either rebuilds on the host (`sha2lato-agent:local`) or pulls the registry image (any other ref) before recreating the stack. CI deploys assume the pull-from-registry mode. See [configuration.md → Deployment modes](configuration.md#deployment-modes).
- **Host-key hardening (optional):** the workflows pin the host key with `ssh-keyscan` at deploy time (trust-on-first-use). For stricter setups, store the host key in a repo secret and replace the `ssh-keyscan` line in `deploy.yml` / `.forgejo/workflows/ci.yml`.
- If the host has local changes, `git pull --ff-only` fails loudly — that's intentional.
- Override the checkout location with `SHA2LATO_DIR` (used by both `bootstrap-host.sh` and `update.sh`).

## Freshness strategy (CVE hygiene)

| Layer | How it stays fresh |
|---|---|
| Base image + system packages | Weekly rebuild pulls the newest `node:24-slim` and apt state; both pipelines republish `:latest` and deploy |
| kimaki / ui-ux-pro-max-cli (npm) | Installed `@latest` at build time — the weekly rebuild refreshes them. Build args can pin versions for reproducible builds instead |
| agents-opencode pack (npm) | Pinned via the `AGENTS_OPENCODE_VERSION` build arg (**manual bump** — Renovate doesn't manage npm installs inside the Dockerfile). After a bump + rebuild, the entrypoint auto-updates the installed pack on the volume (version-tracked marker) |
| graphify CLI (pip `graphifyy`) | Pinned via `GRAPHIFY_VERSION` (manual bump); optional backends via `GRAPHIFY_EXTRAS` (empty = core only). Installed into its own venv at build time |
| ponytail plugin (npm) | Pinned in the entrypoint (`PONYTAIL_SPEC`, default `@dietrichgebert/ponytail@5.2.0`); OpenCode fetches it on first start — bump the spec to update |
| OpenCode | Installed from the official v2 install script at build time (Kimaki requires ≥ 2.0.19; it never pins) |
| CI actions (`actions/*`, `docker/*`) | Renovate PRs (pinned to digests) |
| Docker images (base, dind, linters) | Renovate PRs for the reference tags; **linter images are additionally pinned `tag@digest`** — see below |
| Forgejo job image | Digest-pinned in the workflow; bump the digest to refresh |
| Host OS | `unattended-upgrades` enabled by `bootstrap-host.sh` |

### Linter pinning

The `lint` jobs run these images, pinned `tag@digest` (immutable):

| Tool | Pin (recorded at `ci.yml` time) |
|---|---|
| shellcheck | `koalaman/shellcheck:v0.11.0@sha256:61862eba…` |
| hadolint | `hadolint/hadolint:v2.15.1@sha256:32dac941…` |
| actionlint | `rhysd/actionlint:1.7.12@sha256:b1934ee5…` |

**Update procedure:** `docker pull rhysd/actionlint:NEWTAG` → `docker image inspect rhysd/actionlint:NEWTAG --format '{{index .RepoDigests 0}}'` → replace both `tag` and digest in **both** `ci.yml` files (GitHub + Forgejo) and in `tmp/lint-sim.sh` if present. Renovate does not track digests inside `run:` blocks, so bumps are manual and deliberate.

## Supply chain

Everything this repo builds or runs is pinned or first-party, and was verified against upstream registries:

- **Agent image**: base `node:24-slim` (Docker Official); Docker CLI/buildx/compose from Docker's official apt repo; [kimaki](https://github.com/remorses/kimaki) (MIT), [ui-ux-pro-max-cli](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) (MIT), [OpenCode](https://github.com/anomalyco/opencode) (MIT) from their official release channels.
- **Workflow pack**: [agents-opencode](https://github.com/shahboura/agents-opencode) (MIT; npm `agents-opencode@2.6.0` pinned via build arg; npm provenance attestations via GitHub Actions OIDC trusted publishing).
- **Extras**: [ponytail](https://github.com/DietrichGebert/ponytail) (MIT; npm plugin, pinned spec) and [graphify](https://github.com/Graphify-Labs/graphify) (Apache-2.0; PyPI `graphifyy`, pure-Python wheel, pinned build arg).
- **CI tooling**: actionlint (MIT), hadolint (GPL-3.0), shellcheck (GPL-3.0) — GPL tools are invoked as separate processes only; nothing is linked or redistributed. All three pinned by digest.
- **Forgejo job image**: Docker Official `node:24-bookworm` + Docker's apt repo (official-only reference); community act image documented as an alternative.
- **Optional GitHub runner**: [myoung34/github-runner](https://github.com/myoung34/docker-github-actions-runner) (GPL-3.0 — user-pulled image, not redistributed).
