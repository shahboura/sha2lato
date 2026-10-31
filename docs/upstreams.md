# Upstream index

Every versioned component this box pulls from upstream — what it is, where its version is controlled, and which update lane keeps it fresh. One page, so refreshing the whole stack is a checklist instead of archaeology. Licenses and provenance verification live in [ci-cd.md → Supply chain](ci-cd.md#supply-chain).

## Update lanes (the short version)

| Lane | Covers | What you do |
|---|---|---|
| **Automatic** | CI actions + pinned Docker images | merge Renovate PRs (Mondays) |
| **Scheduled** | Floating build-time deps: base image, npm, apt, kimaki, ui-ux-pro-max, tuistory, bun, playwright, gh, OpenCode, Docker CLI | nothing on CI-deployed hosts — the weekly rebuild republishes `:latest` **and deploys it** (GitHub `rebuild.yml`; Forgejo: cron in `.forgejo/workflows/ci.yml`). No CI deploy: `./deploy/update.sh` ([compose-UI users](compose-ui.md): **Redeploy**) |
| **Manual** | Deliberate pins: graphify CLI, ponytail default, linter + Forgejo job-image digests | bump the pin — workflow pins are commit-only; image pins also need a rebuild/redeploy |
| **Runtime** | Workflow packs, ponytail plugin + critique CLI — no rebuild at all | edit `AGENT_PACK` / `PONYTAIL_SPEC` / `CRITIQUE_VERSION` in `secrets/.env.agent` (or your compose UI's `.env` editor) + `up -d` to recreate — env files are re-read on recreate, not on a plain restart ([compose-UI users](compose-ui.md): **Redeploy**). Leave `CRITIQUE_VERSION` unset to track the newest release each start |

## Image substrate (build-time — `agent/Dockerfile`)

| Component | Upstream | License | Installed via | Version control | Updates how |
|---|---|---|---|---|---|
| Base image | [node:26-trixie-slim](https://github.com/nodejs/docker-node) (Docker Official) | MIT | `FROM` | floating tag | weekly rebuild; Renovate |
| npm | [npm/cli](https://github.com/npm/cli) | Artistic-2.0 | `npm -g` @latest (refreshes the base image's bundled npm) | `NPM_VERSION` build arg | weekly rebuild (arg can pin) |
| kimaki | [remorses/kimaki](https://github.com/remorses/kimaki) | MIT | `npm -g` @latest | `KIMAKI_VERSION` build arg | weekly rebuild (arg can pin) |
| ui-ux-pro-max CLI | [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | MIT | `npm -g` @latest | `UIPRO_VERSION` build arg | weekly rebuild (arg can pin) |
| critique CLI | [shahboura/critique](https://github.com/shahboura/critique) (fork) | MIT | GitHub release tarball: `npm install` of the downloaded, sha256-verified `.tgz` into the volume (never the npm registry); not baked in the image | `CRITIQUE_VERSION` env = release `x.y.z` (unset = latest each start) | **runtime** — newest release re-resolved every container start; pin the env var to freeze it |
| tuistory | [remorses/tuistory](https://github.com/remorses/tuistory) | MIT | `npm -g` @latest | `TUISTORY_VERSION` build arg | weekly rebuild (arg can pin) |
| bun | [oven-sh/bun](https://github.com/oven-sh/bun) | MIT | `npm -g` (official npm dist) | `BUN_VERSION` build arg | weekly rebuild (arg can pin) |
| corepack | [nodejs/corepack](https://github.com/nodejs/corepack) | MIT | `npm -g` @latest (no longer in Node 26) | floating | weekly rebuild |
| playwright CLI | [microsoft/playwright](https://github.com/microsoft/playwright) | Apache-2.0 | `npm -g` @latest + `install-deps chromium` | `PLAYWRIGHT_VERSION` build arg | weekly rebuild; browser binaries stay in the volume cache (not the image) |
| GitHub CLI (gh) | [cli/cli](https://github.com/cli/cli) | MIT | official apt repo | floating | weekly rebuild |
| OpenCode 2 | [anomalyco/opencode](https://github.com/anomalyco/opencode) | MIT | official install script | unpinned (kimaki requires ≥ 2.0.19) | weekly rebuild |
| graphify CLI | [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify) | Apache-2.0 | pip `graphifyy==…` into its own venv | `GRAPHIFY_VERSION` (+ `GRAPHIFY_EXTRAS`) | **manual bump** + rebuild |
| Docker CLI trio (cli, buildx, compose) | [Docker's official apt repo](https://download.docker.com/linux/debian) | Apache-2.0 | apt | floating | weekly rebuild |
| Debian packages (git, curl, jq, …) | Debian | varies | apt | floating | weekly rebuild |
| dind sidecar | [docker-library/docker](https://github.com/docker-library/docker) (`docker:29-dind`) | Apache-2.0 | `compose/docker-compose.yml` | image tag | Renovate / manual tag bump |
| Optional GitHub runner | [myoung34/docker-github-actions-runner](https://github.com/myoung34/docker-github-actions-runner) | GPL-3.0 | compose profile | `:latest` tag | Renovate / manual |

Build-arg mechanics: [configuration.md → Build-time](configuration.md#build-time-custom-image).

critique's release tarball ships no lockfile, so its transitive npm dependencies re-resolve from the registry at install time (container start) — the CLI version is pinned, the dependency tree is not.

> npm 12 (the `latest` lane) tightened defaults for every install inside the box: dependency install scripts are denied unless listed (`--allow-scripts` / `allowScripts`), and git/URL dependencies are blocked (`allow-git` / `allow-remote = none`). Symptoms and opt-ins: [troubleshooting.md](troubleshooting.md). Pin `NPM_VERSION=11.x` to keep the old permissive behavior.

## Workflow packs + plugins (runtime — no rebuild)

| Item | Upstream | License | Arrives via | Version control | Updates how |
|---|---|---|---|---|---|
| agents-opencode pack | [shahboura/agents-opencode](https://github.com/shahboura/agents-opencode) | MIT | npm fetch at container start → `/data/opencode/npm` | `AGENT_PACK=agents-opencode` (bare = npm latest per start) | leave bare, or pin `agents-opencode@x.y.z` |
| Superpowers | [obra/superpowers](https://github.com/obra/superpowers) | MIT | git plugin spec in `opencode.json` | `AGENT_PACK=superpowers` (bare = latest tag per start; needs ≥ v6.4.1 on OpenCode v2) | leave bare, or pin `superpowers@vX.Y.Z` |
| Ponytail | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | MIT | OpenCode plugin spec | `PONYTAIL_SPEC` (default `@dietrichgebert/ponytail@5.3.2`) | set `PONYTAIL_SPEC`, or bump the entrypoint default + rebuild |

Grammar and behavior: [usage.md → Workflow pack + extras](usage.md#workflow-pack--extras).

## CI + tooling

| Item | Upstream | Pin lives in | Updates how |
|---|---|---|---|
| shellcheck | [koalaman/shellcheck](https://github.com/koalaman/shellcheck) | `tag@digest` in both `ci.yml` files (+ `test/lint-sim.sh`) | manual digest bump ([procedure](ci-cd.md#linter-pinning)) |
| hadolint | [hadolint/hadolint](https://github.com/hadolint/hadolint) | same | same |
| actionlint | [rhysd/actionlint](https://github.com/rhysd/actionlint) | same | same |
| Forgejo job image | [node:24-bookworm](https://github.com/nodejs/docker-node) (Docker Official) | digest in `.forgejo/workflows/ci.yml` (+ `runner-check.yml`) | manual digest bump |
| GitHub Actions | [actions/*](https://github.com/actions), [docker/*](https://github.com/docker) | pinned tags in `.github/workflows/` | Renovate (pinDigests) |
| Image releases | [googleapis/release-please-action](https://github.com/googleapis/release-please-action) | pinned tag in `.github/workflows/release.yml` | Renovate (pinDigests) — scheme + bootstrap: [versioning.md](versioning.md) |

## Host-level

| Item | Upstream | Notes |
|---|---|---|
| Docker Engine + Compose plugin | [Docker's apt repo](https://docs.docker.com/engine/install/debian/) | installed by `bootstrap-host.sh` from Docker's repo; refresh with `apt upgrade` — not auto-covered by unattended-upgrades' default origins |
| age (optional secrets overlay) | [FiloSottile/age](https://github.com/FiloSottile/age) | **not** installed by this repo — `deploy/age.sh` requires it (distro package or upstream release) |
| Host OS security updates | — | `unattended-upgrades`, enabled by `bootstrap-host.sh` |

## Update everything (checklist)

1. **Merge Renovate PRs** — actions, docker images (dind, base, runner).
2. **Bump deliberate pins if wanted** — `GRAPHIFY_VERSION`, linter digests ([procedure](ci-cd.md#linter-pinning)), Forgejo job-image digest, ponytail default spec. Critique needs no bump: the entrypoint installs the newest release on each start (set `CRITIQUE_VERSION` in `secrets/.env.agent` to freeze one).
3. **Rebuild / redeploy** — `./deploy/update.sh` on the host; CI-deployed users get it from the weekly rebuild (GitHub `rebuild.yml` / Forgejo cron) or dispatch it manually; compose-UI users: **Redeploy**.
4. **Runtime packs** — bare values are already current (re-resolved at every container start); exact pins apply on the next start.
5. **Verify** — CI green, then watch the entrypoint convergence lines in the logs ([troubleshooting.md](troubleshooting.md)).

## Last verified build

2026-10-19, `sha2lato-agent:node26` (linux/amd64, branch `node26-slim`): node 26.12.0 · npm 11.20.0 · corepack 0.36.0 (pnpm 12.14.0 / yarn 1.22.22 via shims) · kimaki 1.2.0 · ui-ux-pro-max-cli 2.15.0 · critique 0.4.0 (npm — the install path has since changed, see the row above) · tuistory 0.12.0 · bun 1.4.3 · playwright 1.64.1 · gh 2.102.0 · graphify 0.9.92 · OpenCode v2.0.32 · python 3.13.5 · docker CLI 29.9.1 · git 2.47.3 — build + in-image smoke (every tool, `critique --web`, a Chromium screenshot, the shims) and `test/lint-sim.sh` green; the arm64 image builds and smokes clean under QEMU too (build-essential path); the Discord gateway leg runs on deploy of this image. Size ≈ 2.0 GB of content (`du`); `docker images` reports ~2.74 GB (daemon accounting) — 0.69 GB less than the 2026-10-18 image (3.42 GB) after pruning source maps/types and critique's unused 3D deps and making `build-essential` arm64-only.
