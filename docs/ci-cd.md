# CI/CD

Two pipelines, one goal: build the agent image for **linux/amd64 + linux/arm64**, publish it to a registry, and deploy it to your host over SSH. Neither pipeline needs a runner you don't already have.

| Pipeline | File | Runs on | Publishes to | Deploys |
|---|---|---|---|---|
| GitHub | `.github/workflows/` | GitHub's free hosted runners (public repo) | GHCR (`ghcr.io/<owner>/sha2lato-agent`) | SSH → `deploy/update.sh` |
| Forgejo | `.forgejo/workflows/ci.yml` | **your existing act_runner** | your Forgejo container registry | SSH → `deploy/update.sh` |

Both run lint + build (multi-arch) + deploy, plus a **weekly rebuild** (Monday 03:17 UTC) that republishes `:latest` with fresh base layers and deploys it, keeping hosts CVE-fresh without code changes. The GitHub pipeline builds each architecture on its own native runner; the Forgejo pipeline builds both on one runner with QEMU (see [runner requirements](#forgejo-runner-requirements)). SemVer releases are cut separately — [versioning.md](versioning.md).

## GitHub pipeline

- **`ci.yml`** — on push to `main`, version tags (`v*`), manual dispatch: runs **`lint`** (shellcheck + hadolint + actionlint, concurrently, in pinned containers) and the reusable **`build.yml`** **in parallel**, then calls **`deploy.yml`** (main only) once both pass.
- **`build.yml`** — reusable, native multi-arch → GHCR: a matrix job per architecture (`ubuntu-24.04` / `ubuntu-24.04-arm`, no QEMU) builds and pushes by digest **with `mode=max` provenance and SBOM attestations**, runs a **smoke test on the pushed image** (arch + version stamp, via the entrypoint, offline), and the `merge` job validates the digests and assembles the multi-arch manifest with the tags: `latest`, `sha-…`, and on version tags `X.Y.Z` / `X.Y` / `X`. A failed smoke test leaves an untagged digest, so an accidentally broken image is never tagged. Serialized per ref (`concurrency: image-publish-…`) so a weekly rebuild and a push can't interleave into a rollback.
- **Hosted arm64 runners are free on public repos.** A *private* fork needs a paid plan or a self-hosted arm64 runner for the `linux/arm64` leg ([runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)).
- **`deploy.yml`** — reusable, **self-skipping**: if `DEPLOY_SSH_HOST` isn't configured it logs a notice and succeeds (forks stay green). Serialized with `concurrency: deploy`.
- **Docker Hub mirror (optional)** — after the manifest is created, `merge` copies the same tag set to `docker.io/<DOCKERHUB_USERNAME>/sha2lato-agent` when both `DOCKERHUB_USERNAME` + `DOCKERHUB_TOKEN` repo secrets are set (self-skipping otherwise, so forks stay green). Docker Hub applies pull rate limits to anonymous consumers — GHCR does not.
- **`release.yml`** — release automation: [release-please](https://github.com/googleapis/release-please) watches `main`, opens a release PR from Conventional Commits, and on merge creates the `vX.Y.Z` tag + GitHub Release. Because `GITHUB_TOKEN`-created tags don't trigger push workflows, it then dispatches `ci.yml` at the tag to publish the semver image tags. Scheme, pinning, bootstrap: [versioning.md](versioning.md).
- **`website.yml`** — optional docs website: builds `website/` and deploys it to Cloudflare Workers when `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` are set (self-skipping otherwise — forks stay green; [website.md](website.md)).
- **`rebuild.yml`** — the weekly cron: build + deploy, no code change required.
- **`renovate.json`** — Renovate opens PRs for base-image and action updates (`pinDigests` on).

**Secrets to set** (repo → Settings → Secrets and variables → Actions): `DEPLOY_SSH_HOST`, `DEPLOY_SSH_USER`, `DEPLOY_SSH_KEY`, optionally `DEPLOY_SSH_PORT`. `GITHUB_TOKEN` is automatic. Optional: `DOCKERHUB_USERNAME` + `DOCKERHUB_TOKEN` enable the Docker Hub mirror. See [secrets.md](secrets.md).

## Forgejo pipeline

- On push to `main`, version tags, the weekly cron, and manual dispatch: **`lint` and `build` (multi-arch) run in parallel**, then `deploy` waits for both. Publishing is not lint-gated (same trade-off as GitHub); the host rollout is. The deploy step has the same self-skipping behavior.
- The Forgejo build emulates arm64 via QEMU on your one runner; GitHub uses native runners (see below). Website: the docs build + Cloudflare deploy job is independent of lint (it self-skips its deploy) and only runs on `main`.
- **Releases:** push a `vX.Y.Z` tag yourself (release-please runs on GitHub only) — this pipeline builds the semver tags. Scheme + pinning: [versioning.md](versioning.md).
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

Component-by-component map — upstream repo, license, pin location, update lane: [upstreams.md](upstreams.md). This section explains the CI machinery behind it.

| Layer | How it stays fresh |
|---|---|
| Base image + system packages | Weekly rebuild pulls the newest `node:26-trixie-slim` and apt state; both pipelines republish `:latest` and deploy |
| Image version | SemVer releases from Conventional Commits (release-please + `release.yml`); the weekly rebuild moves only `:latest` + `:sha-…`, released `X.Y.Z` tags stay frozen — [versioning.md](versioning.md) |
| kimaki / ui-ux-pro-max-cli / critique / tuistory / bun / playwright (npm) | Installed `@latest` at build time — the weekly rebuild refreshes them. Build args can pin versions for reproducible builds instead |
| agents-opencode pack (npm) | Runtime-fetched by the entrypoint, not baked: bare `AGENT_PACK=agents-opencode` tracks npm latest on every container start; pin `agents-opencode@x.y.z` to lock the version (fetched with lifecycle scripts disabled). Cached on the volume; offline starts use the cached copy — the log warns if it differs from a freshly pinned version |
| superpowers plugin (git) | Runtime-fetched by OpenCode from a git tag: bare = latest tag re-resolved each start; pin `superpowers@v7.0.0` for exactness |
| graphify CLI (pip `graphifyy`) | Pinned via `GRAPHIFY_VERSION` (manual bump); optional backends via `GRAPHIFY_EXTRAS` (default `openai` for the DeepSeek/OpenAI semantic pass; empty = core only). Installed into its own venv at build time |
| ponytail plugin (npm) | Pinned in the entrypoint (`PONYTAIL_SPEC`, default `@dietrichgebert/ponytail@5.3.2`); OpenCode fetches it on first start — bump the spec to update |
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

**Update procedure:** `docker pull rhysd/actionlint:NEWTAG` → `docker image inspect rhysd/actionlint:NEWTAG --format '{{index .RepoDigests 0}}'` → replace both `tag` and digest in **both** `ci.yml` files (GitHub + Forgejo) and in `test/lint-sim.sh`. Renovate does not track digests inside `run:` blocks, so bumps are manual and deliberate.

**Local check:** run `test/lint-sim.sh` to reproduce this lint job (wrapper command in its header).

## Supply chain

Everything this repo builds or runs is pinned or first-party, and was verified against upstream registries:

- **Agent image**: base `node:26-trixie-slim` (Docker Official); Docker CLI/buildx/compose from Docker's official apt repo; [kimaki](https://github.com/remorses/kimaki) (MIT), [ui-ux-pro-max-cli](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) (MIT), [OpenCode](https://github.com/anomalyco/opencode) (MIT), [critique](https://github.com/remorses/critique) (MIT), [tuistory](https://github.com/remorses/tuistory) (MIT), [bun](https://github.com/oven-sh/bun) (MIT) and [playwright](https://github.com/microsoft/playwright) (Apache-2.0) from their official release channels, and the [GitHub CLI](https://github.com/cli/cli) (MIT) from its official apt repo.
- **Workflow packs** (runtime-fetched by the entrypoint/OpenCode, never baked): [agents-opencode](https://github.com/shahboura/agents-opencode) (MIT; npm; exact pins supported; registry metadata carries sha512 integrity for each tarball; fetches run with lifecycle scripts disabled; provenance attestations via GitHub Actions OIDC trusted publishing) and [superpowers](https://github.com/obra/superpowers) (MIT; git, tag-pinned).
- **Extras**: [ponytail](https://github.com/DietrichGebert/ponytail) (MIT; npm plugin, pinned spec) and [graphify](https://github.com/Graphify-Labs/graphify) (Apache-2.0; PyPI `graphifyy`, pure-Python wheel, pinned build arg).
- **CI tooling**: actionlint (MIT), hadolint (GPL-3.0), shellcheck (GPL-3.0) — GPL tools are invoked as separate processes only; nothing is linked or redistributed. All three pinned by digest.
- **Release automation**: [release-please-action](https://github.com/googleapis/release-please-action) (Apache-2.0) — turns Conventional Commits into release PRs, tags, and GitHub Releases ([versioning.md](versioning.md)); consumed as a pinned action tag, refreshed by Renovate.
- **Forgejo job image**: Docker Official `node:24-bookworm` + Docker's apt repo (official-only reference); community act image documented as an alternative.
- **Optional GitHub runner**: [myoung34/github-runner](https://github.com/myoung34/docker-github-actions-runner) (GPL-3.0 — user-pulled image, not redistributed).
