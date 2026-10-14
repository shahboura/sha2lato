# Optional: self-hosted GitHub runner

**Default: off.** The GitHub pipeline runs on GitHub's **free hosted runners** (unlimited for public repos), so most people need nothing here. Enable this profile when:

- your GitHub repo is **private** and you'd rather not burn the monthly hosted-runner minutes,
- you want CI builds to run on **your own hardware** (faster arm64, cache locality, no egress),
- or you're fully self-hosting and want the GitHub side to match your Forgejo runner setup.

## Setup

1. Create a **classic PAT** with `repo` scope at <https://github.com/settings/tokens> (org runner: `admin:org`).
2. On the host:

```bash
cd /opt/sha2lato
cp secrets/.env.github-runner.example secrets/.env.github-runner
$EDITOR secrets/.env.github-runner      # REPO_URL + ACCESS_TOKEN
docker compose -f compose/docker-compose.yml --profile github-runner up -d
```

The runner registers itself as `sha2lato-github-runner` with labels `sha2lato,linux`.

## How this repo's workflows use it

The GitHub pipeline doesn't pin itself to your runner by default (hosted runners are the zero-config path). To route builds to your runner instead, edit `.github/workflows/build.yml`:

```yaml
jobs:
  build:
    runs-on: [self-hosted, sha2lato]   # was: ubuntu-latest
```

The runner service mounts the host Docker socket so jobs using `docker` (like this pipeline's lint+build) work — same trust model as your Forgejo build runner: treat it as a personal, single-tenant build machine.

## Notes

- The runner image ([myoung34/github-runner](https://github.com/myoung34/docker-github-actions-runner), GPL-3.0) is pulled from Docker Hub by you — it's not redistributed by this repo.
- To keep a profile-enabled runner running after `./deploy/update.sh`, set `COMPOSE_PROFILES=github-runner` in `compose/.env` so every compose invocation includes it.
- Unregistering: stop the container and remove the runner in the repo/org settings; its data volume (`github-runner-data`) can be deleted.

Docs index: [README](README.md).
