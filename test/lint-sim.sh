#!/usr/bin/env bash
# Simulate the Forgejo lint job locally: job image + docker socket + linters.
# Default image: official node:24-bookworm — the same base image Forgejo CI
# uses (CI pins it by digest; the local wrapper floats the tag on purpose).
# Override for comparison: JOB_IMAGE=catthehacker/ubuntu:act-latest
# Note: the exec-bit guard is not simulated (bind mounts on Windows report
# synthetic exec bits) — both CI lint jobs enforce it.
#
# Versioned tool (test/) — mirrors the CI lint jobs; keep the digest pins in
# sync with both ci.yml files (docs/ci-cd.md → "Linter pinning").
#
# Usage (from repo root):
#   docker run --rm -v "$PWD:/workspace" -w /workspace \
#     -v //var/run/docker.sock:/var/run/docker.sock --entrypoint bash \
#     "${JOB_IMAGE:-node:24-bookworm}" /workspace/test/lint-sim.sh
#
# Daemon-side Docker (DOCKER_HOST to a DinD sidecar, e.g. the agent box):
# "-v $PWD" resolves on the DAEMON's filesystem — the mount comes up empty.
# Pipe the repo in instead (same job image + socket pattern):
#   tar -czf - --exclude=./secrets --exclude=./data --exclude=./tmp -C "$PWD" . | docker run --rm -i \
#     -v //var/run/docker.sock:/var/run/docker.sock --entrypoint bash \
#     "${JOB_IMAGE:-node:24-bookworm}" \
#     -c 'mkdir -p /workspace && tar -xzf - -C /workspace && cd /workspace && bash test/lint-sim.sh'
set -e

echo "--- job image: $(cat /etc/os-release 2>/dev/null | head -1) ---"

echo '--- setup: Docker CLI + Buildx (official Docker apt repo) ---'
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck source=/dev/null
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends docker-ce-cli docker-buildx-plugin
else
  echo "(docker CLI already in image)"
fi

echo '--- preflight: daemon via socket ---'
[ -f agent/Dockerfile ] || { echo 'FAIL: run from the repo root (wrapper in the header)'; exit 1; }
docker info >/dev/null 2>&1 || { echo 'FAIL: no Docker daemon in the socket (see the wrapper in the header)'; exit 1; }
echo 'docker daemon: OK'

fail=0

echo '--- shellcheck via stdin (same set as the CI lint jobs) ---'
for f in agent/entrypoint.sh deploy/*.sh test/lint-sim.sh; do
  echo "checking $f"
  if ! cat "$f" | docker run --rm -i koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d -; then
    fail=1
    echo "FAIL: $f"
  fi
done
[ "$fail" -eq 0 ] && echo 'shellcheck: CLEAN'

echo '--- hadolint via stdin ---'
if docker run --rm -i hadolint/hadolint:v2.15.1@sha256:32dac94127fd60b7b7e3fbfc65e1383b9b5e25c9bfd7b8536de7a539fe68a12d < agent/Dockerfile; then
  echo 'hadolint: CLEAN'
else
  fail=1
fi

echo '--- actionlint via stdin (all workflows) ---'
for f in .github/workflows/*.yml .forgejo/workflows/*.yml; do
  echo "checking $f"
  if ! cat "$f" | docker run --rm -i rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667 -stdin-filename "$f" -; then
    fail=1
  fi
done
[ "$fail" -eq 0 ] && echo 'actionlint: CLEAN'

echo
if [ "$fail" -eq 0 ]; then
  echo '=== SIMULATION COMPLETE: ALL LINTERS CLEAN ==='
else
  echo '=== SIMULATION COMPLETE: FINDINGS ABOVE ==='
  exit 1
fi
