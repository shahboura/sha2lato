# AGENTS.md — sha2lato

sha2lato is a self-hosted "agent box": Kimaki (Discord → OpenCode 2) + the
ui-ux-pro-max skill in one Docker image, with a DinD sidecar so the agent can
build and run project images. Multi-arch CI on GitHub + Forgejo, SSH deploys,
weekly CVE-fresh rebuilds. Public repo (MIT), fork-friendly.

## Conventions for agents working in this repo

- **Line endings + exec bits:** LF everywhere; authored on Windows, runs on
  Linux. Shell scripts must be committed executable (`100755`) — from Windows
  use `git add --chmod=+x`; CI lint guards enforce it.
- **Secrets:** never commit real `.env*` files, `secrets/ssh/` contents, age
  private keys, or `data/`. Only `*.example` files, `secrets/age/*.age` and
  `secrets/age/recipient` are committable. Personal values live in
  `secrets/*.env` and `compose/.env` (gitignored).
- **One custom image:** `agent/` is the only Dockerfile. Everything else is
  official images wired by `compose/docker-compose.yml`.
- **Impersonal compose:** keep it fork-friendly — no personal values; use
  `secrets/*.env` (env_file) and `compose/.env` (interpolation).
- **Supply chain:** every dependency is first-party (Docker Official images,
  official apt repos/installers) or pinned (`tag@digest`, versioned build
  args) — do not add unpinned third-party images without documenting the
  trade-off.
- **Validate changes** (from repo root): `docker compose -f
  compose/docker-compose.yml config --quiet`; `test/lint-sim.sh` (full CI-job
  simulation — lint via the same job image + socket pattern CI uses; copy the
  wrapper command from its header); markdown links must resolve.
- **Verify + review:** every change gets the review cycle (fresh lenses)
  before commit; external claims — CLI flags, APIs, upstream syntax — are
  confirmed against current upstream docs, not memory.
- **Docs:** main `README.md` is marketing-flavored; `docs/*.md` are practical
  and scoped. Update the docs index when adding a doc. Diagrams use Mermaid
  (renders natively on GitHub and Forgejo).
- **Knowledge graph:** when `graphify-out/graph.json` exists, use
  `graphify query` / `path` / `explain` before broad grepping. After code
  edits run `graphify update .` (free); after doc edits run
  `graphify extract . --backend deepseek` and `graphify label .`. If the
  graph is absent, skip it silently.
- **Config UX:** convention over configuration — the only required value is
  the bot token; every knob has one override point (`secrets/.env.agent` via
  `deploy/configure.sh`); users never edit compose/Dockerfile.
- **Long Docker builds / validations:** run them in separate subagents
  (parallel when independent) so verbose build logs stay out of the main
  context; have them report compact pass/fail summaries and sizes.

## Current state

The box is complete and review-gated: agent image (Kimaki + OpenCode 2 +
ui-ux-pro-max + ponytail + graphify + the box tools: critique, tuistory, bun,
playwright CLI + chromium deps, gh), compose stack (agent + DinD, explicit
volume names), secrets + age overlay, GitHub + Forgejo CI (multi-arch, weekly
rebuild, fork-safe), host bootstrap/update/configure scripts, and scoped docs.
`AGENT_PACK` uses `pack[@version]` — `agents-opencode` (default; runtime npm
latest) / `superpowers` (latest git tag) / `none`; exact pins supported.
`PONYTAIL=1` and `GRAPHIFY=1` default on; `GRAPHIFY_EXTRAS=openai` defaults on
so graphify's semantic pass can use `DEEPSEEK_API_KEY`/`OPENAI_API_KEY`.
Agent commits use a baked identity (`sha2lato agent`) and can be SSH-signed
with `GIT_SIGN=1`. Public on GitHub; CI green; multi-arch image on GHCR.
Forgejo CI is wired but the runner leg is deferred.

## Session log

Detailed history lives in git and the Discord transcripts; keep one short
entry per session here.

- **2026-10-14 (session 1):** Built the image, compose stack, secrets/age
  overlay, GitHub + Forgejo CI, host scripts, and docs. Settled workflow packs
  behind `AGENT_PACK`; added ponytail + graphify extras; fixed a 684 MB npm
  cache leak (image 2.47 → 1.65 GB). GitHub CI green, GHCR published;
  deployment modes + Arcane docs landed after 4 review cycles.
- **2026-10-15 (session 2):** Consolidated packs to
  `AGENT_PACK=<pack>[@<version>]` (runtime fetch, offline cache) and promoted
  the lint simulation to `test/lint-sim.sh`, wired into both CI lints. Caught
  and fixed the missing dind `docker` network alias; full-stack sandbox pass.
- **2026-10-17 (session 3):** Added Discord onboarding docs and the entrypoint
  `normalize_external_directory()` fix — agents-opencode 3.0.0 wrote a blanket
  v2 `deny`; the entrypoint now converges it to `ask` on every start.
- **2026-10-18 (session 4):** Moved to `node:24-trixie-slim` (GLIBCXX
  3.4.33), baked critique/tuistory/bun/playwright/gh, added the external-dir
  allow-list, refreshed docs. Kimaki 1.2.0; tool smokes + tokenless e2e pass.
  arm64 native fallbacks need `build-essential` (baked). Retired the
  `/root/.config/opencode` symlink (agents-opencode 3.1.0 false positive).
  Triaged dind noise and switched its healthcheck to `docker version`.
  Baked graphify's `openai` extra; built the repo graph (91 nodes) and added
  the graphify convention above.
- **Open:** deploy the rebuilt image; retest `upload-to-discord` on kimaki
  1.2.0; file the drafted kimaki issues (tunnel DNS, upload bug); Forgejo
  runner leg.
