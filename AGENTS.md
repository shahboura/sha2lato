# AGENTS.md — sha2lato

sha2lato is a self-hosted "agent box": Kimaki (Discord → OpenCode 2) + the
ui-ux-pro-max skill in one Docker image, with a DinD sidecar so the agent can
build and run project images. Multi-arch CI on GitHub + Forgejo, SSH deploys,
weekly CVE-fresh rebuilds. Public repo (MIT), fork-friendly.

Deploying the box rather than developing it? Point your agent at `docs/agent-setup.md` — a setup guide written to be executed by agents.

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
- **Commits:** Conventional Commits — `feat:`/`fix:`/`chore:`/`docs:` (scope
  optional), `!` or a `BREAKING CHANGE:` trailer marks a major image release.
  release-please turns merges into version bumps; released `vX.Y.Z` tags are
  never re-pushed ([versioning.md](docs/versioning.md)).
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
  `graphify extract . --backend deepseek --token-budget 10000` and
  `graphify label .` — the token budget is load-bearing: the default 60k
  packs the whole docs corpus into one LLM call and returns thin per-file
  coverage, which the extractor's shrink guard then refuses to write. The
  guard still trips on LLM variance (same command, fewer nodes): check the
  node diff and pass `--allow-partial`, or rebuild into a scratch `--out`
  dir and swap `graph.json`. If the graph is absent, skip it silently.
- **Config UX:** convention over configuration — the only required value is
  the bot token; every knob has one override point (`secrets/.env.agent` via
  `deploy/configure.sh`); users never edit compose/Dockerfile.
- **Long Docker builds / validations:** run them in separate subagents
  (parallel when independent) so verbose build logs stay out of the main
  context; have them report compact pass/fail summaries and sizes.

## Sharing diffs

In-chat diffs are the default. `critique --web "<title>"` uploads to the
self-hosted instance only when `CRITIQUE_WORKER_URL` is set (operator sets it
in `secrets/.env.agent` or the compose-UI env editor, then recreates the
agent). Unset or empty falls back to the third-party `critique.work` — keep
diffs in chat then.

## Current state

The box is complete and review-gated: agent image (Kimaki + OpenCode 2 +
ui-ux-pro-max + ponytail + graphify + the box tools: critique, tuistory, bun,
playwright CLI + chromium deps, gh), compose stack (agent + DinD, explicit
volume names), secrets + age overlay, GitHub + Forgejo CI (multi-arch, weekly
rebuild, fork-safe), host bootstrap/update/configure scripts, and scoped docs.
A docs website (`website/`, Holocron) renders from the same `README.md` +
`docs/*.md` and deploys to Cloudflare Workers when the CF secrets are set
(optional, fork-safe; upstream instance live at `sha2lato.elkodr.com`);
`docs/commands.md` is the command reference and `docs/agent-setup.md` the
agent-executable setup runbook.
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
- **2026-10-19 (session 5):** Docs revamp + optional docs website. The Arcane
  page became a generic compose-UI guide; added `docs/commands.md`
  (box-verified command reference), `docs/website.md`, and
  `docs/agent-setup.md` (agent-executable setup runbook, human-readable too);
  freshness pass (`agents-opencode@3.1.2` examples, MDX-safe autolinks). New
  Holocron site (`website/`) renders from the same `README.md` + `docs/*.md`,
  deploys to Cloudflare Workers via fork-safe jobs in **both** CI pipelines;
  verified locally (build, wrangler dry-run, smoke, lint-sim). Four review
  lenses; all findings triaged and fixed (range-based change detection,
  redirect coverage, contrast tokens).
- **2026-10-19 (session 6, branch `node26-slim`):** Base image →
  `node:26-trixie-slim` (Node 26.12.0; LTS on 2026-10-28) and the measured
  slim-down findings applied: corepack installed from npm (Node 26 no longer
  ships it), `*.map`/`*.d.ts` pruned in the npm layer, critique's unused
  3D/WebGPU optional deps removed, `build-essential` arm64-only. Do **not**
  prune `test` dirs — playwright exports `lib/mcp/test` at runtime — and do
  not drop the mesa/LLVM chain from `playwright install-deps`: purging it
  breaks headless Chromium (exit 127). Image 3.42 → 2.74 GB
  (`docker images`); build + in-image smoke (tools, `critique --web`,
  Chromium screenshot, pnpm/yarn shims) + `test/lint-sim.sh` green; the arm64
  image also builds and smokes clean under QEMU (with `build-essential`).
- **2026-10-19 (session 7):** Critique self-hosting wiring (env-template
  placeholder + docs), docs-site Dependabot fix (branch
  `fix/dependabot-alerts`), and SemVer image versioning: release-please cuts
  releases from Conventional Commits (`X.Y.Z`/`X.Y`/`X` tags; `latest` +
  `sha-…` unchanged), version stamp baked into the image and both pipelines;
  `v1.0.0` tagged and published (`docs/versioning.md`).
- **2026-10-22 (session 8):** CI parallelism + native multi-arch build.
  `ci.yml` runs `lint` and `build` in parallel (deploy gated on both; the
  three linters run concurrently in one step, GitHub + Forgejo). `build.yml`
  rebuilt as a native amd64/arm64 matrix (`ubuntu-26.04` / `ubuntu-26.04-arm`,
  no QEMU) → push-by-digest → smoke test of the pushed image (arch + version
  stamp, `--network none`, hardened) → digest artifacts → `merge` job
  assembles the manifest (2 regular 64-hex files validated, per-ref publish
  concurrency). Attestations pinned explicitly (`provenance: mode=max` +
  `sbom: true`; the action already defaults to max on public repos, min on
  private). Optional Docker Hub mirror in the merge job, self-skipping
  without the `DOCKERHUB_*` secrets. Runner labels pinned to 26.04; the lint
  jobs pass actionlint an `-ignore` for those labels (1.7.12 predates them).
  OCI labels restored in the build legs; version
  label == build stamp (docs/versioning corrected). GitHub action majors bumped
  (checkout v7, login/buildx v4, metadata v6, build-push v7) and Renovate now
  SHA-pins Actions; Forgejo stays on the older action majors until its
  act_runner supports Node 24. Forgejo mirrors the
  parallelism but keeps its single-runner QEMU build. `test/lint-sim.sh`
  green; smoke flags validated against `sha2lato-agent:npm-pr`.
- **Open:** deploy the rebuilt image; retest `upload-to-discord` on kimaki
  1.2.0; file the drafted kimaki issues (tunnel DNS, upload bug); Forgejo
  runner leg; verify self-hosted critique uploads once `diff.<domain>`
  resolves (`CRITIQUE_WORKER_URL` wiring is in place).
