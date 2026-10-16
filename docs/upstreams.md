# Upstream index

Every component this box pulls from upstream — what it is, where its version is controlled, and which update lane keeps it fresh. One page, so refreshing the whole stack is a checklist instead of archaeology. Licenses and provenance verification live in [ci-cd.md → Supply chain](ci-cd.md#supply-chain).

## Update lanes (the short version)

| Lane | Covers | What you do |
|---|---|---|
| **Automatic** | CI actions + pinned Docker images | merge Renovate PRs (Mondays) |
| **Scheduled** | Floating build-time deps: base image, apt, kimaki, ui-ux-pro-max, OpenCode, Docker CLI | nothing — the weekly `rebuild.yml` republishes `:latest`; redeploy on the host (or Arcane → Redeploy) picks it up |
| **Manual** | Deliberate pins: graphify CLI, linter digests, ponytail default spec | bump the pin, rebuild/redeploy |
| **Runtime** | Workflow packs + ponytail plugin — no rebuild at all | edit `AGENT_PACK` / `PONYTAIL_SPEC` in `secrets/.env.agent` (or the Arcane `.env` editor) + restart |

## Image substrate (build-time — `agent/Dockerfile`)

| Component | Upstream | License | Installed via | Version control | Updates how |
|---|---|---|---|---|---|
| Base image | [node:24-slim](https://github.com/nodejs/docker-node) (Docker Official) | MIT | `FROM` | floating tag | weekly rebuild; Renovate |
| kimaki | [remorses/kimaki](https://github.com/remorses/kimaki) | MIT | `npm -g` @latest | `KIMAKI_VERSION` build arg | weekly rebuild (arg can pin) |
| ui-ux-pro-max CLI | [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | MIT | `npm -g` @latest | `UIPRO_VERSION` build arg | weekly rebuild (arg can pin) |
| OpenCode 2 | [anomalyco/opencode](https://github.com/anomalyco/opencode) | MIT | official install script | unpinned (kimaki requires ≥ 2.0.19) | weekly rebuild |
| graphify CLI | [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify) | Apache-2.0 | pip `graphifyy==…` into its own venv | `GRAPHIFY_VERSION` (+ `GRAPHIFY_EXTRAS`) | **manual bump** + rebuild |
| Docker CLI trio (cli, buildx, compose) | [Docker's official apt repo](https://download.docker.com/linux/debian) | Apache-2.0 | apt | floating | weekly rebuild |
| Debian packages (git, curl, jq, …) | Debian | varies | apt | floating | weekly rebuild |
| dind sidecar | [docker-library/docker](https://github.com/docker-library/docker) (`docker:29-dind`) | Apache-2.0 | `compose/docker-compose.yml` | image tag | Renovate / manual tag bump |
| Optional GitHub runner | [myoung34/docker-github-actions-runner](https://github.com/myoung34/docker-github-actions-runner) | GPL-3.0 | compose profile | `:latest` tag | Renovate / manual |

Build-arg mechanics: [configuration.md → Build-time](configuration.md#build-time-custom-image).

## Workflow packs + plugins (runtime — no rebuild)

| Item | Upstream | License | Arrives via | Version control | Updates how |
|---|---|---|---|---|---|
| agents-opencode pack | [shahboura/agents-opencode](https://github.com/shahboura/agents-opencode) | MIT | npm fetch at container start → `/data/opencode/npm` | `AGENT_PACK=agents-opencode` (bare = npm latest per start) | leave bare, or pin `agents-opencode@x.y.z` |
| Superpowers | [obra/superpowers](https://github.com/obra/superpowers) | MIT | git plugin spec in `opencode.json` | `AGENT_PACK=superpowers` (bare = latest tag per start; needs ≥ v6.4.1 on OpenCode v2) | leave bare, or pin `superpowers@vX.Y.Z` |
| Ponytail | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | MIT | OpenCode plugin spec | `PONYTAIL_SPEC` (default `@dietrichgebert/ponytail@5.2.0`) | set `PONYTAIL_SPEC`, or bump the entrypoint default + rebuild |

Grammar and behavior: [usage.md → Workflow pack + extras](usage.md#workflow-pack--extras).

## CI + tooling

| Item | Upstream | Pin lives in | Updates how |
|---|---|---|---|
| shellcheck | [koalaman/shellcheck](https://github.com/koalaman/shellcheck) | `tag@digest` in both `ci.yml` files (+ `tmp/lint-sim.sh`) | manual digest bump ([procedure](ci-cd.md#linter-pinning)) |
| hadolint | [hadolint/hadolint](https://github.com/hadolint/hadolint) | same | same |
| actionlint | [rhysd/actionlint](https://github.com/rhysd/actionlint) | same | same |
| Forgejo job image | [node:24-bookworm](https://github.com/nodejs/docker-node) (Docker Official) | digest in `.forgejo/workflows/ci.yml` | manual digest bump |
| GitHub Actions | [actions/*](https://github.com/actions), [docker/*](https://github.com/docker) | pinned tags in `.github/workflows/` | Renovate (pinDigests) |

## Host-level

| Item | Upstream | Notes |
|---|---|---|
| Docker Engine + Compose plugin | [Docker's apt repo](https://docs.docker.com/engine/install/debian/) | installed by `bootstrap-host.sh`; refresh with the distro |
| age (optional secrets overlay) | [FiloSottile/age](https://github.com/FiloSottile/age) | **not** installed by this repo — `deploy/age.sh` requires it (distro package or upstream release) |
| Host OS security updates | — | `unattended-upgrades`, enabled by `bootstrap-host.sh` |

## Update everything (checklist)

1. **Merge Renovate PRs** — actions, docker images (dind, base, runner).
2. **Bump manual pins if wanted** — `GRAPHIFY_VERSION`, linter digests ([procedure](ci-cd.md#linter-pinning)), Forgejo job-image digest, ponytail default spec.
3. **Rebuild / redeploy** — `./deploy/update.sh` on the host; CI-only users: the Monday rebuild does it (or dispatch `rebuild.yml`); Arcane users: **Redeploy**.
4. **Runtime packs** — bare values are already current (re-resolved at every container start); exact pins apply on the next start.
5. **Verify** — CI green, then watch the entrypoint convergence lines in the logs ([troubleshooting.md](troubleshooting.md)).

## Last verified build

2026-10-15, `sha2lato-agent:local` (linux/amd64): kimaki 1.0.0 · ui-ux-pro-max-cli 2.15.0 · OpenCode v2.0.28 · python 3.11.2 · docker CLI 29.9.0 · git 2.39.5.
