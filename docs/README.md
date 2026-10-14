# sha2lato — documentation index

New here? Read **1 → 2**, run `./deploy/configure.sh`, and you're running in ~10 minutes. Everything else is scoped reference.

| # | Scope | What it covers |
|---|---|---|
| 1 | [Hosting](hosting.md) | Bring-your-own Docker host (primary) + Azure VM (turnkey flavor); firewall (ufw), sizing, day-2 ops |
| 2 | [Discord bot](discord-bot.md) | Creating and self-hosting your own bot identity; access control |
| 3 | [Secrets](secrets.md) | `*.env` strategy, git SSH keys, deploy keys (Forgejo + GitHub), age overlay, fork checklist |
| 4 | [Configuration](configuration.md) | Convention over configuration: every knob in one place, the configure script, build-time args |
| 5 | [CI/CD](ci-cd.md) | GitHub + Forgejo pipelines, registries, deploy mechanism, freshness strategy, linter pinning, Forgejo runner requirements, supply chain |
| 6 | [Usage](usage.md) | Day-2 from your phone: new projects from Discord, workflow packs, queue/btw/worktrees/diff/tunnels, multi-machine |
| 7 | [GitHub runner (optional)](github-runner.md) | Enabling the self-hosted GitHub runner profile |
| 8 | [Troubleshooting](troubleshooting.md) | Symptom → cause → fix tables for every subsystem |
