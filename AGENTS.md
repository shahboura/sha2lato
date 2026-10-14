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
  compose/docker-compose.yml config --quiet`; `tmp/lint-sim.sh` (full CI-job
  simulation — lint via the same job image + socket pattern CI uses);
  markdown links must resolve.
- **Docs:** main `README.md` is marketing-flavored; `docs/*.md` are practical
  and scoped. Update the docs index when adding a doc. Diagrams use Mermaid
  (renders natively on GitHub and Forgejo).
- **Config UX:** convention over configuration — the only required value is
  the bot token; every knob has one override point (`secrets/.env.agent` via
  `deploy/configure.sh`); users never edit compose/Dockerfile.

## Current state

Complete and review-gated (3 adversarial cycles, all findings resolved):
agent image (kimaki + opencode 2 + ui-ux-pro-max + optional workflow packs),
compose stack (agent + DinD), secrets + age overlay, GitHub + Forgejo CI
(multi-arch, weekly rebuild, fork-safe), host bootstrap/update/configure
scripts, 9 scoped docs. Workflow packs are selected via a single
`AGENT_PACK` env (agents-opencode | superpowers, mutually exclusive). Zero
commits so far. The maintainer's detailed working state lives in `HANDOFF.md`
— gitignored, local checkout only (not present in clones/forks).

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
