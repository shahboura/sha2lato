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
- **Config UX:** convention over configuration — the only required value is
  the bot token; every knob has one override point (`secrets/.env.agent` via
  `deploy/configure.sh`); users never edit compose/Dockerfile.
- **Long Docker builds / validations:** run them in separate subagents
  (parallel when independent) so verbose build logs stay out of the main
  context; have them report compact pass/fail summaries and sizes.

## Current state

Complete and review-gated (4 adversarial cycles incl. a dedicated security
pass, plus parallel-agent validation; all findings resolved): agent image
(kimaki + opencode 2 + ui-ux-pro-max substrate, plus ponytail and graphify)
built down to ~1.6 GB,
compose stack (agent + DinD, explicit volume names), secrets + age overlay,
GitHub + Forgejo CI (multi-arch, weekly rebuild, fork-safe), host
bootstrap/update/configure scripts, 11 scoped docs. `AGENT_PACK` uses a
`pack[@version]` grammar — `agents-opencode` (default; bare = npm latest,
fetched at runtime to the volume) / `superpowers` (bare = latest git tag) /
`none`, exact pins supported; `PONYTAIL=1` and
`GRAPHIFY=1` extras are on by default and toggleable; agent commits use a
baked identity (`sha2lato agent`) and can be SSH-signed via `GIT_SIGN=1`
(`SHA2LATO_AGENT_IMAGE` selection → docs/configuration.md → Deployment
modes). Pushed to GitHub (public): CI green, multi-arch image published to
GHCR. Forgejo leg deferred.

## Initial commit recipe (Windows authoring → Linux exec bits)

```bash
git add -A
git add --chmod=+x agent/entrypoint.sh deploy/update.sh deploy/bootstrap-host.sh deploy/age.sh deploy/configure.sh
git commit -m "Initial release"
```

The CI lint jobs fail loudly if a future commit drops an exec bit.
Commits may be SSH-signed (git ≥ 2.34: `gpg.format ssh` + `user.signingkey` +
`commit.gpgsign true`) — nothing in the repo depends on signatures either way.

## Session log

- **2026-10-14 (session 1):** Planned with owner and built everything end to
  end: agent image (verified by real local builds + smoke tests), compose
  stack (agent + DinD, smoke-tested healthy), secrets scaffolding + age
  overlay, GitHub CI (reusable build/deploy, weekly rebuild, fork-safe
  self-skip) and Forgejo CI (mirror, official-only job image, stdin linters —
  validated by full local job simulations), host bootstrap + update +
  configure scripts, 9 scoped docs (incl. configuration + multi-machine with
  Mermaid diagrams), and the validation gate: 3 adversarial review cycles
  (exec-bit guards, sudo-proof ufw, healthcheck env, permissions scoping,
  pack XDG-path fix, pack `external_directory` restoration, version-tracked
  pack marker — all fixed and re-verified). Workflow packs wired as a single
  `AGENT_PACK` selector (owner's agents-opencode pack baked in / superpowers
  plugin), mutually exclusive with enforced worktree rules. Awaiting owner's
  first commit.
- **2026-10-14 (session 1, continued):** Added workflow extras with defaults
  on — ponytail (plugin spec) and graphify (baked CLI + usage guide) — made
  `AGENT_PACK` default to agents-opencode (adds `none`), extended
  `configure.sh`, and fixed a hidden 684 MB npm-cache bloat (image 2474 →
  1645 MB, smaller than the pre-graphify baseline). arm64 wheels and the full
  toggle matrix verified via parallel subagents. First commit made
  (`7739ffb Initial release`); the extras batch is uncommitted.
- **2026-10-14 (session 1, continued 2):** Pushed to GitHub (public); CI
  green end-to-end (exec-bit guards, linters, multi-arch build+push to GHCR,
  deploy self-skip). Delivered the deployment-mode batch: `update.sh` mode
  detection + `--dry-run`, `configure.sh` image-mode choice, canonical
  Deployment-modes docs, explicit volume names (rename-safe under UI
  managers), and `docs/arcane.md` (running under a Docker management UI —
  two recipes + one-owner rule). Forgejo leg deferred; firewall/SSH flags
  still parked.
- **2026-10-14 (session 1, continued 3):** Cycle-4 review (adversarial +
  security in parallel): no blockers; `opencode debug config` empirically
  confirmed OpenCode v2 honors the pack/permission config (resolves to the
  normalized `permissions` array), and V2's global config path is the volume
  path. Fixes: Arcane token-in-store warning, mode-aware bootstrap banner +
  ci-cd pseudocode, CRLF trimming in the scripts, real volume names in docs,
  privileged-DinD notes, least-privilege workflow secret passing. Security
  audit: only `.example` files tracked, tree clean.
- **2026-10-14 (session 1, continued 4):** Self-hosting under Arcane
  documented end-to-end; added a baked agent commit identity
  (`GIT_USER_NAME`/`GIT_USER_EMAIL` overrides) plus optional SSH commit
  signing (`GIT_SIGN=1`, dedicated `secrets/ssh/signing_key`). Cycle-6 review
  (adversarial + security, parallel): both GO/SAFE-TO-COMMIT; smoke tests
  proved a signed commit object inside the image. Review fixes applied
  (option-safe config values, Forgejo key semantics, verification wording).
- **2026-10-15 (session 2):** Consolidated the workflow-pack config into one
  grammar — `AGENT_PACK=<pack>[@<version>]` — removing the coupled knobs:
  `SUPERPOWERS_TAG` (deprecation warning if still set) and the
  `AGENTS_OPENCODE_VERSION` build arg (pack no longer baked; fetched at
  runtime into `/data/opencode/npm`, bare = npm latest re-resolved each
  start, offline falls back to the cached copy). superpowers bare = latest
  git tag; spec upsert now replaces prior entries so tag switches converge.
  DRY'd three duplicated jq plugin merges into
  `set_plugin_spec`/`remove_plugin_specs` helpers. Validated: lint-sim ALL
  CLEAN, 57 doc links resolve, image rebuilt (1.72 GB), 11/11 container smoke
  checks pass (offline warm/cold, tag-switch convergence, invalid values,
  deprecation, uninstall). Review gate (adversarial + security, parallel)
  cycle 1 — fixes applied: `AGENT_PACK=none` now strips the superpowers entry;
  exclusivity strip gated on the agents pack being healthy; empty-suffix `@`
  warnings; git-ref validation (`sp_tag_ok`) on superpowers pins AND resolved
  tags; latest excludes prereleases; `--ignore-scripts` on the npm fetch;
  atomic same-volume config writes; `XDG_CACHE_HOME` on the volume (plugin
  clones offline-safe). Re-verified: lint-sim CLEAN + 10-check fresh smoke
  matrix (none-strip, invalid-pin keeps superpowers, empty suffixes, `..`
  rejected, --ignore-scripts install, cache env). Follow-ups: runtime-pack pin
  note in `docs/arcane.md` and a new `docs/upstreams.md` component/update-lane
  index (cross-linked from README + ci-cd). Cycle-2 review (docs batch +
  upstream-doc verification) — fixed: index accuracy (`up -d` not restart for
  env changes, deploy semantics, `tmp/lint-sim.sh`/`runner-check.yml`
  locations, host Docker apt wording), `sp_tag_ok` leading-dash guard,
  Renovate cron syntax (Later syntax deprecated), npm-integrity wording.
  Verified against current upstream docs: npm flags, git `ls-remote`/`sort` +
  `check-ref-format`, Renovate docker-compose manager + `pinDigests`, OpenCode
  plugin spec, dind TLS pattern, XDG `XDG_CACHE_HOME`. Promoted the local lint
  simulation from gitignored `tmp/` into versioned `test/lint-sim.sh`, wired
  into both CI lint jobs (GitHub + Forgejo: shellcheck lists + exec-bit
  guards) — its digest pins now live in a tracked file; `tmp/` is scratch-only
  again. Sandbox full-stack close-the-gap test caught + fixed a real DinD
  networking bug (the `dind` service lacked the `docker` network alias that
  `DOCKER_HOST` expects — agent→DinD was unreachable); fix verified live
  including `docker run --rm hello-world` through DinD. Stage B (full-stack,
  throwaway volumes): fresh compose up → DinD + agent healthy → pack fetched
  (2.6.0, npm latest) → kimaki `gateway shard 0 ready` (self-hosted mode;
  guilds pending invite) → torn down + volumes wiped.
- **2026-10-17 (session 3):** Discord onboarding docs + permission normalization.
  (1) `docs/discord-bot.md`: added a "What you need on Discord" mental model and
  step 0 (create your server) — the assumed-knowledge gap; docs index row
  updated. (2) Entrypoint: new `normalize_external_directory()` converges the
  global `external_directory` rule to OpenCode v2's canonical `permissions`
  array (`{"action":"external_directory","resource":"*","effect":"ask"}`,
  appended last — last-match-wins) on every start; drops the pack's blanket
  deny and the legacy v1 `external_directory` entry (deprecated `permission`
  key only when empty; unrelated rules/keys survive); never-abort guards. Root
  cause: agents-opencode 3.0.0 writes the v2 array with `deny` — silently
  blocking cross-directory flows (a deny cannot be overridden by Discord
  buttons). Validated: 8-case dash harness in the agent image (caught + fixed a
  real jq nesting bug; idempotency + `set -e` survival test), shellcheck +
  lint-sim ALL CLEAN, compose config, doc links; review gate (adversarial +
  security) — no blockers, all findings applied. Investigations (no changes):
  `docker:29-dind` log warnings all expected upstream (embedded containerd,
  nft/fsverity benign); kimaki "3 catalog shortcuts" benign (skills dropped
  first at Discord's 100 cap); OpenCode version drift = build-time latest +
  runtime self-update. Open: deployment shows a persistent `docker`-hostname
  DNS failure from the agent container (suspect the deployed compose predates
  the dind `docker` alias) + the permission fix needs redeploy there.
