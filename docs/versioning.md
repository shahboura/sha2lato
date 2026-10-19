# Image versioning & releases

The agent image is versioned with **SemVer**, automated from **Conventional
Commits**: you merge normal PRs, release-please proposes the version, and
merging its release PR tags the release and builds the semver image tags.
One-time bootstrap excepted — see [Maintainer notes](#maintainer-notes).

## Scheme

| Bump | When it applies | Examples |
|---|---|---|
| **MAJOR** | Breaking operator contract: compose service/volume/secrets layout, required env changes, data or volume migration, entrypoint behavior that breaks existing installs | renaming a volume; dropping an env var |
| **MINOR** | New capability or notable upstream jump | new baked tool; Node/OpenCode major; new deployment mode |
| **PATCH** | Fixes that keep the contract | bug fix; dependency bump |

Commit messages drive the bump (`!` or a `BREAKING CHANGE:` trailer = MAJOR):

| Commit | Release |
|---|---|
| `feat: …` | MINOR |
| `fix: …`, `perf: …` | PATCH |
| `chore: …`, `docs: …`, `ci: …` | no release (next release batches it) |
| `feat!: …` / any type with `BREAKING CHANGE:` | MAJOR |

## Tags (GHCR / Forgejo registry)

All semver tags come from git tags `vX.Y.Z` (release PR merges):

| Tag | Points at | Moves? |
|---|---|---|
| `X.Y.Z` | one released commit | **never** — released tags are immutable |
| `X.Y` | newest patch of that line | on patch releases |
| `X` | newest minor of that major | on minor/patch releases |
| `latest` | newest build from `main`, **including weekly CVE rebuilds** | every main push / rebuild |
| `sha-<short>` | one commit | never |

Pinning guide for `SHA2LATO_AGENT_IMAGE`:

- `:latest` — auto CVE-fresh (weekly rebuild); surprises possible
- `:X` / `:X.Y` — change control with patch/minor freshening
- `:X.Y.Z` — frozen; security rebuilds arrive as a new patch release

The weekly rebuild republishes only `latest` and `sha-…`: a released `X.Y.Z`
stays the same artifact forever. If a released version needs a CVE refresh,
cut a new patch release (a `fix:` commit is enough) — never re-tag.

## How a release happens (GitHub)

```text
feat:/fix: commits -> main  ->  release-please opens/updates "chore: release vX.Y.Z"
                                        | merge
                                        v
                              tag vX.Y.Z + GitHub Release + CHANGELOG.md
                                        |
                                release.yml dispatches
                                        v
                       ci.yml on the tag -> build.yml -> GHCR X.Y.Z, X.Y, X
```

The dispatch is deliberate: GitHub does not start workflows for tags pushed
with `GITHUB_TOKEN`, so `release.yml` triggers the tagged build explicitly
instead of relying on the `v*` push trigger. A maintainer-pushed tag (or
Forgejo's pipeline, which builds `v*` directly) works without the dispatch.

Troubleshooting a release: if the release PR doesn't appear, check that
commits use Conventional Commit prefixes — release-please ignores the rest.
The tag list on GHCR is visible in the package page; `gh release list` shows
GitHub releases.

## Check the version of a running box

```bash
# on a released tag the OCI label carries the version:
docker inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' ghcr.io/OWNER/sha2lato-agent:1.4.2
docker compose -f compose/docker-compose.yml exec agent printenv SHA2LATO_VERSION
# or look for the "[entrypoint] sha2lato <version>" line in the logs
```

On `:latest` the OCI label reads `latest` (the highest-priority tag rule wins)
— use `printenv` or the entrypoint line there.

## Maintainer notes

- **Bootstrap (one time):** the current box is `1.0.0` (`version.txt` +
  `.release-please-manifest.json`). After the versioning PR merges, tag that
  commit and push it once: `git tag v1.0.0 && git push origin v1.0.0`
  (optionally `gh release create v1.0.0 --generate-notes`), then run
  `gh workflow run release.yml` once so release-please recomputes with the tag
  as its baseline. Until the tag exists, its first automatic run can see the
  full history — a spurious PR from that window updates (or close it) once the
  tag lands. Every later release is automated.
- **Never re-tag or rebuild a released `vX.Y.Z`** — immutability is what makes
  version pinning meaningful.
- **Forgejo-only setups:** releases are cut by pushing the tag yourself
  (`git tag vX.Y.Z && git push origin vX.Y.Z`); the Forgejo pipeline already
  builds `v*` tags. release-please itself is GitHub-only.
- Config lives in `release-please-config.json` +
  `.release-please-manifest.json`; `version.txt` is the version file that
  release-please bumps.
