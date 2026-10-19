# Baked-in tools & commands

Everything listed here is **preinstalled** in the agent image — version pins and update lanes live in [upstreams.md](upstreams.md).

Two surfaces reach the toolset:

- **Discord slash commands** — fixed Kimaki commands (`/login`, `/diff`, …) plus dynamic ones from the active OpenCode catalog: agents as `/<name>-agent` (primary agents only — subagents are skipped), commands as `/<name>-cmd`, skills as `/<name>-skill`; Kimaki caps the combined surface at 100.
- **In-session shell** — the agent runs any CLI below; you can too via `! <cmd>` in a Discord channel (raw, in the project folder) or `docker compose -f compose/docker-compose.yml exec agent <cmd>` on the host.

Pack-dependent entries are marked **`AGENT_PACK`** / **`PONYTAIL`** / **`GRAPHIFY`** — the switches live in `secrets/.env.agent` ([configuration.md](configuration.md#every-knob)).

## Kimaki — Discord front end + CLI

Kimaki is the bot itself ([remorses/kimaki](https://github.com/remorses/kimaki)); its CLI is on the agent's PATH in every session. Fixed Discord commands (registered by Kimaki, independent of the active pack):

| Command | What it does |
|---|---|
| `/login`, `/transcription-key` | Connect a model provider / set the voice transcription key |
| `/model`, `/model-variant`, `/agent`, `/verbosity` | Model, thinking level, agent, bot output (session or channel) |
| `/diff` | Git diff of the session folder as a shareable URL (critique backend) |
| `/resume`, `/new-session`, `/session-id`, `/cwd` | Session lifecycle — resume, start, locate, change working dir |
| `/queue`, `/btw` / `/abort`, `/clear-queue` | Queue work / side question; stop a run / drop the queue |
| `/undo`, `/redo`, `/compact`, `/context-usage` | History and context tools |
| `/fork`, `/fork-subagent` / `/new-worktree`, `/merge-worktree`, `/worktrees` | Branch out — fork sessions; worktree lifecycle |
| `/routines` | Scheduled prompts — list, run one now, or delete |

CLI examples (agent-run in-session, or from the host via `docker compose … exec agent`):

| Command | What it does |
|---|---|
| `kimaki status` / `logs -f` / `restart` | Health, log file (follow), restart — sessions keep running |
| `kimaki project add /data/projects/app` | Create a channel for a directory |
| `kimaki session list --all` / `session read <id> --thinking` | Sessions with token counts / transcript as markdown |
| `kimaki session diff` / `session command <name>` | Publish the session git diff / run a command, skill, or MCP prompt |
| `kimaki tunnel -- pnpm dev` | Expose a local port with a public URL |
| `kimaki sleep --duration 2h --reason "watch deploy"` / `routine list` | Wake later / scheduled prompts (`run <id>` runs one now) |
| `kimaki upload-to-discord <files…>` | Attach local files to the thread |

## OpenCode 2

The agent engine Kimaki drives. The TUI runs as `docker compose -f compose/docker-compose.yml exec -it agent opencode`; from a session shell you can also run:

| Command | What it does |
|---|---|
| `opencode run --prompt "summarize this repo"` | One-shot agent run |
| `opencode models` / `serve` | List available models / v2 API + web server |
| `opencode upgrade` | Upgrade OpenCode itself |

## graphify — code → knowledge graph

**`GRAPHIFY=1`** (default) adds the usage-guide skill; the CLI is always baked ([Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify)). For a large or unfamiliar repo, tell the agent **“graph this repo first”** — or run:

| Command | What it does |
|---|---|
| `graphify extract . --code-only` | Build the graph, local AST only (no API key); for the semantic LLM pass add `--backend deepseek` (or your configured key) |
| `graphify update .` | Refresh after code edits (no LLM) |
| `graphify query "how does auth work"` | Answer by traversing the graph |
| `graphify path "A" "B"` / `explain "X"` / `affected "X"` / `god-nodes` | Shortest path / node + neighbors / reverse impact / connected hubs |
| `graphify label .` / `cluster-only .` | (Re)name communities; `export html` for the visual |

Graphs are per-checkout in `graphify-out/` (keep it out of git).

## Ponytail — lazy senior dev mode

**`PONYTAIL=1`** (default) pins [ponytail](https://github.com/DietrichGebert/ponytail) as a plugin; it layers on any pack. In Discord add the usual suffix (`/ponytail-review-cmd`):

| Command | What it does |
|---|---|
| `/ponytail [lite \| full \| ultra \| off]` | Set intensity, or turn it off (no argument: keeps the current level) |
| `/ponytail-review` / `/ponytail-audit` | Review the current diff / the whole repo, ranked — bugs, security, missing tests, what to cut |
| `/ponytail-debt` | Collect deferred `shortcut:` comments into a ledger |
| `/ponytail-gain`, `/ponytail-help` | Impact scoreboard / quick reference |

## critique — the diff viewer behind /diff

`/diff` and `kimaki session diff` publish through [critique](https://github.com/remorses/critique); the CLI also runs standalone (or via `bunx critique` anywhere bun runs) — bare, it shows a local TUI diff:

| Command | What it does |
|---|---|
| `critique main HEAD --web "Branch changes"` | Publish a web diff, prints the URL |
| `critique <PR URL> --web` | Review a GitHub PR without checking it out |
| `critique hunks list` / `hunks add <ids>` / `login <key>` | Selective staging by stable hunk IDs / license key for unlimited links |

Flags: `--staged`, `--commit <ref>`, `--pdf`, `--image`, `--json`, `--password` (or `CRITIQUE_PASSWORD`).

## tuistory — named background terminal sessions

Persistent PTY sessions in a background daemon ([remorses/tuistory](https://github.com/remorses/tuistory)) — the pattern for keeping dev servers alive (see [usage.md](usage.md#everyday-workflows) → Tunnels):

| Command | What it does |
|---|---|
| `tuistory launch "kimaki tunnel -- pnpm dev" -s myapp-dev` | Start a named session |
| `tuistory read -s myapp-dev` (`--follow`) / `snapshot --trim` / `screenshot -s myapp-dev -o shot.png` | New output (block until output) / screen as text / as PNG |
| `tuistory type` / `press` / `click` / `wait` / `scroll` | Drive TUI apps programmatically |
| `tuistory sessions` / `close -s …` / `attach` | Manage sessions (they persist until closed) |

## Playwright — headless browser CLI

| Command | What it does |
|---|---|
| `playwright install chromium` | One-time per browser revision; binaries cache on `/data` |
| `playwright screenshot <url> <file>` / `pdf <url> <file>` | Headless screenshot / page → PDF |
| `playwright codegen <url>` / `test` / `mcp` | Record a script / run Playwright Test / MCP server |

## Bun + bunx

| Command | What it does |
|---|---|
| `bun install` / `add <pkg>` | Install dependencies (bun lockfiles) |
| `bun run <script>` / `test` / `check` | Scripts / tests / type check |
| `bunx <tool>` | Run a package binary, installing it if needed |

## GitHub CLI (gh)

| Command | What it does |
|---|---|
| `gh auth login` | Authenticate gh and git with GitHub |
| `gh pr`, `gh issue`, `gh repo` / `gh run`, `gh workflow` | Pull requests, issues, repos / Actions |
| `gh api`, `gh gist`, `gh search` | Raw API, gists, search |

## Docker tooling (DinD)

The CLI speaks to the **DinD sidecar**, isolated from your host daemon ([usage.md](usage.md) → Docker-based projects):

| Command | What it does |
|---|---|
| `docker build` / `run` / `ps` / `compose up -d` | Build, run, and inspect images; compose stacks (publish `0.0.0.0`, connect via `docker:<port>`) |
| `docker compose -f compose/docker-compose.yml exec dind docker image prune -af` | Free sidecar disk from the host |

## agents-opencode pack — agents, commands, skills

**`AGENT_PACK=agents-opencode`** (default) installs the [agents-opencode](https://github.com/shahboura/agents-opencode) framework (10 agents / 16 commands / 27 skills in the current pack; see [usage.md](usage.md#workflow-pack--extras) for the `superpowers` alternative).

**Agents** — delegation targets `@codebase` (implementation), `@planner`, `@review`, `@researcher`, `@docs`, `@brutal-critic`, `@legal-advisor`; in Discord the primaries get switches (`/orchestrator-agent`, `/blogger-agent`, `/em-advisor-agent`).

**Commands** (TUI `/name`, Discord `/name-cmd`):

| Command | Use |
|---|---|
| `/plan-project` | Multi-phase project planning |
| `/execution-loop` / `/stop-loop` | Bounded iterative execution / stop + summarize state |
| `/checkpoint` | Phase-boundary checkpoint for a human decision |
| `/code-review` / `/security-audit` | Code review / security audit |
| `/generate-tests`, `/refactor-plan`, `/architecture-review` | Tests, refactors, architecture |
| `/api-docs`, `/create-readme`, `/architecture-decision` | API documentation, README, ADRs |
| `/blog-post`, `/content-review`, `/1-on-1-prep`, `/legal-review` | Content, meetings, compliance |

**Skills** — 27 on-demand skills (11 language, 16 workflow) load only when invoked; in Discord `/name-skill`.

## ui-ux-pro-max — design intelligence

A baked skill family ([nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)): `ui-ux-pro-max`, plus `design`, `design-system`, `ui-styling`, `banner-design`, `brand`, `slides`. Ask for design work (“build a landing page”, “pick a palette”) and the agent loads the skill on demand; the stdlib-only Python script queries its local dataset (79 styles, 192 product palettes, 74 font pairings, 119 UX guidelines, 105 icons, 17 GSAP presets, 25 chart types, 22 stacks) as `python3 /data/opencode/config/opencode/skills/ui-ux-pro-max/scripts/search.py "<query>" …`:

| Query | What it returns |
|---|---|
| `… --design-system` | Full design system: pattern, style, colors, typography |
| `… --domain style` | One focused answer (domains: product, style, typography, color, landing, chart, ux, gsap, react, web, icons, google-fonts) |
| `… --stack nextjs` | Stack rules (stacks: react, nextjs, vue, svelte, astro, swiftui, react-native, flutter, nuxtjs, nuxt-ui, html-tailwind, shadcn, jetpack-compose, threejs, angular, laravel, javafx, wpf, winui, avalonia, uno, uwp) |

Add `--persist -p "<Name>" --output-dir "<project-root>"` to save a design system into the project for later sessions.

## Everyday one-liners

| Command | What it does |
|---|---|
| `! <cmd>` (Discord) / `docker compose -f compose/docker-compose.yml exec agent <cmd>` | Run any shell command raw — in the project folder / from the host |
| `pnpm` / `yarn` | corepack shims — respect the project's `packageManager` field |

Also baked: `git`, `node` 24, `python3` (the skills' search scripts are stdlib Python), `jq`, `curl`, `unzip`, `openssh-client`, `corepack`.
