---
name: graphify-usage
description: Use when exploring an unfamiliar or large codebase, planning a cross-cutting change, or answering questions that span many files — build or query a local knowledge graph with the graphify CLI instead of re-reading files.
---

# Graphify usage

`graphify` turns a project into a queryable knowledge graph. Code is parsed locally with tree-sitter AST — deterministic, no model calls, nothing leaves the machine. Prefer it over grepping and file-by-file reading on anything beyond a handful of files.

## Build / refresh

- Build: `graphify extract .` — add `--code-only` to stay fully offline (skips docs/images that would need a model pass).
- Communities + report: `graphify cluster-only .` writes `GRAPH_REPORT.md` (god nodes, communities, suggested questions) and the interactive `graph.html`.
- Refresh incrementally after changes: `graphify update .`
- Everything lands in `graphify-out/` (`graph.json` is the graph itself; `cache/` makes re-runs incremental).

## Query the graph (prefer over re-reading)

- `graphify query "<question>"` — scoped subgraph for a plain-language question
- `graphify path "<A>" "<B>"` — how two things connect
- `graphify explain "<name>"` — one node and its connections
- Every edge is tagged `EXTRACTED` (explicit in the source) or `INFERRED` (derived) — you always know what was read versus guessed.

## Rules of thumb

- First contact with a repo of more than a few dozen files, or before a broad refactor: build the graph, then read `GRAPH_REPORT.md`.
- Ask graph queries before grepping; fall back to plain search for exact strings.
- Keep `graphify-out/` out of git — add it to the project's `.gitignore`.
- Worktrees: the graph is per-checkout. Build or update it inside the worktree you are working in.
- The CLI is baked into this box. Run `graphify --help` for the full command set (PR dashboard, wiki export, git hooks, MCP server).
