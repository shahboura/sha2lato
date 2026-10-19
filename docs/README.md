# sha2lato — documentation index

New here? Read **1 → 2**, run `./deploy/configure.sh`, and you're running in ~10 minutes. Everything else is scoped reference.

| # | Scope | What it covers |
|---|---|---|
| 1 | [Hosting](hosting.md) | Bring-your-own Docker host (primary) + Azure VM (turnkey flavor); firewall (ufw), sizing, day-2 ops |
| 2 | [Discord bot](discord-bot.md) | Creating your Discord server + self-hosting your own bot identity; access control |
| 3 | [Secrets](secrets.md) | `*.env` strategy, git SSH keys, deploy keys (Forgejo + GitHub), age overlay, fork checklist |
| 4 | [Configuration](configuration.md) | Convention over configuration: every knob in one place, the configure script, build-time args |
| 5 | [CI/CD](ci-cd.md) | GitHub + Forgejo pipelines, registries, deploy mechanism, freshness strategy, linter pinning, Forgejo runner requirements, supply chain |
| 6 | [Usage](usage.md) | Day-2 from your phone: new projects from Discord, workflow packs, queue/btw/worktrees/diff/tunnels, multi-machine |
| 7 | [GitHub runner (optional)](github-runner.md) | Enabling the self-hosted GitHub runner profile |
| 8 | [Deploy with Docker Compose and management UIs](compose-ui.md) | Running the same compose file under a management UI (Arcane, Dockge, Portainer, …): two recipes, the one-owner rule, UI shell access |
| 9 | [Troubleshooting](troubleshooting.md) | Symptom → cause → fix tables for every subsystem |
| 10 | [Upstreams](upstreams.md) | Every dependency: upstream repo, license, pin location, and the four update lanes — plus a full-refresh checklist |
| 11 | [Baked-in tools & commands](commands.md) | Every preinstalled CLI, plugin, and slash command with verified examples |
| 12 | [Docs website (optional)](website.md) | Holocron site built from these docs, deployed to Cloudflare Workers — local dev, CI deploy, custom domains |
| 13 | [Agent-driven setup](agent-setup.md) | Point an agent at it and it can deploy the box end to end — human-in-the-loop steps, exact commands, verification |
