# syntax=docker/dockerfile:1
# sha2lato agent box — Kimaki + OpenCode 2 + ui-ux-pro-max, Docker-ready.
#
# Design notes:
# - Base: node:26-trixie-slim (Debian 13, Node 26 — LTS from 2026-10-28).
#   Kimaki's own Dockerfile stays on bookworm; trixie is chosen here for GCC
#   14's libstdc++ (GLIBCXX 3.4.33), which native prebuilds (critique/
#   tree-sitter) require.
# - Agent tools baked for kimaki features: critique (diff viewer), tuistory
#   (background sessions), bun, playwright CLI + chromium system deps
#   (headless screenshots — install browsers with `playwright install`; they
#   persist in the /data volume cache via XDG_CACHE_HOME), GitHub CLI, corepack.
# - The runtime substrate installs at build time; weekly CI rebuilds keep it
#   fresh (CVEs). Workflow packs (AGENT_PACK) are NOT baked — the entrypoint
#   fetches them at runtime (npm/git) into the volume, so pack versions are
#   configuration, not build args.
# - Substrate versions default to "latest" but can be pinned via build args
#   for reproducible builds.
# - State (kimaki.db, OpenCode sessions/auth, projects) lives on the /data
#   volume, NOT in the image — rebuilds never log you out.
# - The ui-ux-pro-max skill is baked into /opt/skills and synced into the
#   OpenCode global skills dir by entrypoint.sh on every start, so image
#   rebuilds update the skill while user-added skills on the volume survive.

FROM node:26-trixie-slim

ARG DEBIAN_FRONTEND=noninteractive
# Pin for reproducible builds; "latest" by design (weekly rebuilds refresh)
ARG KIMAKI_VERSION=latest
ARG UIPRO_VERSION=latest
ARG CRITIQUE_VERSION=latest
ARG TUISTORY_VERSION=latest
ARG BUN_VERSION=latest
ARG PLAYWRIGHT_VERSION=latest
ARG GRAPHIFY_VERSION=0.9.92
# graphify extras, comma-separated (e.g. "leiden,mcp"). Default openai powers the
# semantic LLM pass with DEEPSEEK_API_KEY/OPENAI_API_KEY; empty = core only.
ARG GRAPHIFY_EXTRAS=openai

# bash with pipefail for every RUN env (predictable failures on pipes)
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ── System packages ────────────────────────────────────────────────────────
# git, curl, unzip, ca-certificates  : required by kimaki / opencode
# openssh-client                     : git over SSH (Forgejo/GitHub deploy keys)
# python3                            : ui-ux-pro-max search scripts (stdlib only)
# build-essential (arm64 only)       : node-gyp fallback builds — arm64 npm deps
#                                      without prebuilds (critique's tree-sitter
#                                      grammars). amd64 resolves prebuilds, so it
#                                      is skipped there (~61 MB); an agent that
#                                      must compile installs it on demand (root
#                                      container, network access)
# docker-ce-cli + buildx + compose   : docker CLI for the DinD sidecar, so the
#                                      agent can build AND run project images
# gh                                 : GitHub CLI from its official apt repo —
#                                      issue/PR workflows, gist evidence
# apt versions intentionally unpinned — weekly image rebuilds track security fixes
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git openssh-client unzip python3 python3-venv jq; \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
        apt-get install -y --no-install-recommends build-essential; \
    fi; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc; \
    chmod a+r /etc/apt/keyrings/docker.asc; \
    . /etc/os-release; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        docker-ce-cli docker-buildx-plugin docker-compose-plugin; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends gh; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# ── Kimaki + agent tooling (runtime substrate) ─────────────────────────────
# Workflow packs are fetched by the entrypoint at runtime, not baked here.
# critique: diff-viewer backend for kimaki /diff (docs: "not bundled")
# tuistory: named background sessions (the kimaki tunnel pattern)
# bun:      bun-lockfile projects, bunx-based tools (profano, ...)
# playwright: headless browser CLI for screenshots; browser binaries are NOT
#   baked — run `playwright install chromium` once per revision and they land
#   in the /data volume cache (XDG_CACHE_HOME below), surviving rebuilds and
#   matching whatever version a project or the CLI needs.
# corepack: not shipped in node:26 (it left the distribution; the npm package
#   is the supported install) — still needed for the pnpm/yarn shims below.
# All pruning happens in the SAME layer as the install: Docker layers are
# additive, so a later `rm` would not reclaim the bytes. The npm cache alone
# is ~680 MB. Source maps and type declarations are never read at runtime
# (~186 MB); licenses and package metadata stay for redistribution. Do NOT
# prune "test" dirs: playwright exports its test runner at runtime (lib/mcp/
# test, the playwright/test entrypoint). critique's TUI pulls a separately
# imported 3D/WebGPU entry (three/planck/bun-webgpu/@dimforge, ~60 MB) that
# the diff path never loads.
RUN npm install -g kimaki@${KIMAKI_VERSION} ui-ux-pro-max-cli@${UIPRO_VERSION} \
        critique@${CRITIQUE_VERSION} tuistory@${TUISTORY_VERSION} \
        bun@${BUN_VERSION} playwright@${PLAYWRIGHT_VERSION} corepack@latest \
    && npm cache clean --force \
    && rm -rf /root/.npm \
    && find /usr/local/lib/node_modules -type f \
         \( -name '*.map' -o -name '*.d.ts' \) -delete \
    && rm -rf \
         /usr/local/lib/node_modules/critique/node_modules/{three,planck,bun-webgpu,bun-webgpu-linux-x64,@dimforge}

# ── Chromium system deps + corepack shims ──────────────────────────────────
# playwright install-deps pulls the X/GTK libraries Chromium needs (official
# per-distro mapping — handles trixie's package renames); corepack provides
# pnpm/yarn shims for worktree auto-install and repos that pin their manager.
# Keep the mesa/LLVM chain this pulls in: purging it makes headless Chromium
# fail to start (exit 127 — libgbm/libGL missing), tested 2026-10-19.
RUN corepack enable \
    && playwright install-deps chromium \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── OpenCode 2 (kimaki requires >= 2.0.19) ─────────────────────────────────
RUN curl -fsSL https://opencode.ai/v2/install | bash
ENV PATH="/root/.opencode/bin:${PATH}"

# ── Keep OpenCode state on the /data volume ────────────────────────────────
# XDG_CACHE_HOME keeps fetched plugin clones (e.g. superpowers) on the volume
# too — offline starts after a container recreate keep working.
ENV XDG_DATA_HOME=/data/opencode/data \
    XDG_STATE_HOME=/data/opencode/state \
    XDG_CONFIG_HOME=/data/opencode/config \
    XDG_CACHE_HOME=/data/opencode/cache

# No legacy ~/.config/opencode symlink: kimaki (>= 1.2) and the
# agents-opencode installer (>= 3.1) both honor XDG_CONFIG_HOME. A symlink at
# the legacy path made the installer report "installs at BOTH paths" and
# advise deleting them — through the link that deletes the active install.

# ── Bake the ui-ux-pro-max skill ───────────────────────────────────────────
# Scratch install runs in a tmpfs mount, so uipro's working files never land
# in an image layer. entrypoint.sh syncs /opt/skills into the global OpenCode
# skills dir at start. The final test fails the build loudly if the skill did
# not install where we expect it — better than shipping an image without it.
WORKDIR /build
RUN --mount=type=tmpfs,target=/build set -eux; \
    uipro init --ai opencode --offline; \
    mkdir -p /opt/skills; \
    for d in .opencode/skills .claude/skills .agents/skills; do \
        if [ -d "$d" ]; then cp -r "$d"/. /opt/skills/; fi; \
    done; \
    test -n "$(find /opt/skills -name 'SKILL.md' -print -quit)"

# ── Bake graphify (code → queryable knowledge graph CLI) ───────────────────
# Pure-Python wheel (py3-none-any), installed into its own venv because
# Debian is PEP 668 externally-managed. Exposed on PATH as `graphify`.
# GRAPHIFY_EXTRAS pulls optional backends at build time (leiden, mcp, ...).
RUN set -eux; \
    python3 -m venv /opt/graphify; \
    if [ -n "${GRAPHIFY_EXTRAS}" ]; then \
        SPEC="graphifyy[${GRAPHIFY_EXTRAS}]==${GRAPHIFY_VERSION}"; \
    else \
        SPEC="graphifyy==${GRAPHIFY_VERSION}"; \
    fi; \
    /opt/graphify/bin/pip install --no-cache-dir --disable-pip-version-check "$SPEC"; \
    rm -rf /opt/graphify/lib/python3.*/site-packages/pip \
           /opt/graphify/lib/python3.*/site-packages/pip-*.dist-info \
           /opt/graphify/bin/pip*; \
    ln -s /opt/graphify/bin/graphify /usr/local/bin/graphify; \
    test -x /opt/graphify/bin/graphify; \
    /opt/graphify/bin/graphify --help >/dev/null

# ── Bake the graphify usage guide (synced to the volume by the entrypoint) ──
COPY skills-graphify /opt/skills-graphify

# ── Layout, git identity & entrypoint ──────────────────────────────────────
# System gitconfig gives agent-made commits a working default identity —
# override with GIT_USER_NAME/GIT_USER_EMAIL (docs/usage.md).
RUN test -f /opt/skills-graphify/graphify-usage/SKILL.md \
    && mkdir -p /data/projects \
    && git config --system user.name "sha2lato agent" \
    && git config --system user.email "agent@sha2lato.local"
WORKDIR /data

COPY entrypoint.sh /usr/local/bin/sha2lato-entrypoint
RUN chmod 0755 /usr/local/bin/sha2lato-entrypoint

# ── Build-time smoke ───────────────────────────────────────────────────────
# The npm-layer pruning is only safe while every baked CLI still starts; fail
# the build (weekly rebuild included) instead of shipping a broken tool.
RUN export XDG_DATA_HOME=/tmp/smoke XDG_STATE_HOME=/tmp/smoke \
           XDG_CONFIG_HOME=/tmp/smoke XDG_CACHE_HOME=/tmp/smoke; \
    node -v && npm -v && python3 -V && corepack --version \
    && kimaki --help >/dev/null && critique --help >/dev/null \
    && tuistory --version && bun --version && playwright --version \
    && graphify --help >/dev/null && opencode --version

# No EXPOSE: the bot connects OUT to Discord; docker builds go through the
# DinD sidecar (DOCKER_HOST); the kimaki lock port is container-internal.
HEALTHCHECK --interval=60s --timeout=15s --start-period=60s --retries=3 \
    CMD ["sh", "-c", "kimaki status --data-dir \"${KIMAKI_DATA_DIR:-/data}\""]

ENTRYPOINT ["/usr/local/bin/sha2lato-entrypoint"]
