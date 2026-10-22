# Optional: self-hosted GitHub runner

**Default: off.** The GitHub pipeline runs on GitHub's **free hosted runners** (unlimited for public repos), so most people need nothing here. Enable this profile when:

- your GitHub repo is **private** and you'd rather not burn the monthly hosted-runner minutes,
- you want CI builds to run on **your own hardware** (faster arm64, cache locality, no egress),
- or you're fully self-hosting and want the GitHub side to match your Forgejo runner setup.

## Setup

1. Create a **classic PAT** with `repo` scope at [github.com/settings/tokens](https://github.com/settings/tokens) (org runner: `admin:org`).
2. On the host:

```bash
cd /opt/sha2lato
cp secrets/.env.github-runner.example secrets/.env.github-runner
$EDITOR secrets/.env.github-runner      # REPO_URL + ACCESS_TOKEN
docker compose -f compose/docker-compose.yml --profile github-runner up -d
```

The runner registers itself as `sha2lato-github-runner` with labels `sha2lato,linux`.

## How this repo's workflows use it

The GitHub pipeline doesn't pin itself to your runner by default (hosted runners are the zero-config path). Two jobs would need editing:

```yaml
jobs:
  build:
    runs-on: [self-hosted, sha2lato]   # was: ${{ matrix.runner }}
  merge:
    runs-on: [self-hosted, sha2lato]   # was: ubuntu-24.04
```

A single x86_64 runner serves only the `linux/amd64` leg: the `linux/arm64` leg then fails in buildx unless the host has binfmt/QEMU registered (re-add `docker/setup-qemu-action` for that, at emulation speed). For both arches natively, add an arm64 runner and point the matrix's `linux/arm64` entry at its label instead. The `merge` job only needs registry access — it can stay on a hosted runner.

The runner service mounts the host Docker socket so jobs using `docker` (like this pipeline's lint+build) work — same trust model as your Forgejo build runner: treat it as a personal, single-tenant build machine.

## Notes

- The runner image ([myoung34/github-runner](https://github.com/myoung34/docker-github-actions-runner), GPL-3.0) is pulled from Docker Hub by you — it's not redistributed by this repo.
- To keep a profile-enabled runner running after `./deploy/update.sh`, set `COMPOSE_PROFILES=github-runner` in `compose/.env` so every compose invocation includes it.
- Unregistering: stop the container and remove the runner in the repo/org settings; its data volume (`sha2lato-github-runner-data`) can be deleted.

Docs index: [README](README.md).
