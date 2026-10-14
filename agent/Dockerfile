# syntax=docker/dockerfile:1
# sha2lato agent box — Kimaki + OpenCode 2 + ui-ux-pro-max, Docker-ready.
#
# Design notes:
# - Base: node:24-slim (Debian) — the same base Kimaki's own Dockerfile uses.
# - Everything installs at build time; weekly CI rebuilds keep it fresh (CVEs).
# - Versions default to "latest" but can be pinned via build args for
#   reproducible builds.
# - State (kimaki.db, OpenCode sessions/auth, projects) lives on the /data
#   volume, NOT in the image — rebuilds never log you out.
# - The ui-ux-pro-max skill is baked into /opt/skills and synced into the
#   OpenCode global skills dir by entrypoint.sh on every start, so image
#   rebuilds update the skill while user-added skills on the volume survive.

FROM node:24-slim

ARG DEBIAN_FRONTEND=noninteractive
# Pin for reproducible builds; "latest" by design (weekly rebuilds refresh)
ARG KIMAKI_VERSION=latest
ARG UIPRO_VERSION=latest
ARG AGENTS_OPENCODE_VERSION=2.6.0
ARG GRAPHIFY_VERSION=0.9.90
# Optional graphify backends, comma-separated (e.g. "leiden,mcp"); empty = core only
ARG GRAPHIFY_EXTRAS=

# bash with pipefail for every RUN env (predictable failures on pipes)
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ── System packages ────────────────────────────────────────────────────────
# git, curl, unzip, ca-certificates  : required by kimaki / opencode
# openssh-client                     : git over SSH (Forgejo/GitHub deploy keys)
# python3                            : ui-ux-pro-max search scripts (stdlib only)
# docker-ce-cli + buildx + compose   : docker CLI for the DinD sidecar, so the
#                                      agent can build AND run project images
# apt versions intentionally unpinned — weekly image rebuilds track security fixes
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git openssh-client unzip python3 python3-venv jq; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc; \
    chmod a+r /etc/apt/keyrings/docker.asc; \
    . /etc/os-release; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        docker-ce-cli docker-buildx-plugin docker-compose-plugin; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# ── Kimaki + ui-ux-pro-max CLI + agents-opencode pack ──────────────────────
# The npm cache is purged in the SAME layer: Docker layers are additive, so a
# later `rm` would not reclaim it — without this it adds ~680 MB to the image.
RUN npm install -g kimaki@${KIMAKI_VERSION} ui-ux-pro-max-cli@${UIPRO_VERSION} agents-opencode@${AGENTS_OPENCODE_VERSION} \
    && npm cache clean --force \
    && rm -rf /root/.npm

# ── OpenCode 2 (kimaki requires >= 2.0.19) ─────────────────────────────────
RUN curl -fsSL https://opencode.ai/v2/install | bash
ENV PATH="/root/.opencode/bin:${PATH}"

# ── Keep OpenCode state on the /data volume ────────────────────────────────
ENV XDG_DATA_HOME=/data/opencode/data \
    XDG_STATE_HOME=/data/opencode/state \
    XDG_CONFIG_HOME=/data/opencode/config

# Some tools (e.g. the agents-opencode installer) target ~/.config/opencode
# regardless of XDG_CONFIG_HOME — symlink it onto the volume-backed XDG path
# so everything converges on /data/opencode/config/opencode.
RUN mkdir -p /root/.config && ln -sfn /data/opencode/config/opencode /root/.config/opencode

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
    test -x /opt/graphify/bin/graphify

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

# No EXPOSE: the bot connects OUT to Discord; docker builds go through the
# DinD sidecar (DOCKER_HOST); the kimaki lock port is container-internal.
HEALTHCHECK --interval=60s --timeout=15s --start-period=60s --retries=3 \
    CMD ["sh", "-c", "kimaki status --data-dir \"${KIMAKI_DATA_DIR:-/data}\""]

ENTRYPOINT ["/usr/local/bin/sha2lato-entrypoint"]
