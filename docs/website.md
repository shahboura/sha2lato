# Docs website

The repo also ships a **documentation website** built from the same markdown you are reading: [`website/`](../website/) is a [Holocron](https://holocron.so) site whose pages are thin MDX wrappers that import `README.md` and `docs/*.md` directly. **One source of truth** — a doc edit updates GitHub, Forgejo, *and* the site; nothing is copied or generated at build time.

The site deploys as a **Cloudflare Worker** (`sha2lato-docs`) via `wrangler`. It is **optional**: forking, ignoring, or deleting `website/` does not affect the box. CI skips the deploy when the Cloudflare secrets are unset, so forks stay green.

| File | What it is |
|---|---|
| `website/docs.json` | Site config: name, colors, fonts, navigation groups |
| `website/global.css` | Theme tokens — dark-first, light mode included |
| `website/src/*.mdx` | One wrapper per page: frontmatter + an import of the real doc |
| `website/vite.config.ts` | Holocron + Cloudflare Vite plugins (`pagesDir: ./src`) |
| `website/wrangler.jsonc` | Worker name, entrypoint, compatibility flags — no account id |
| `website/public/` | SVG logo (light/dark wordmark) + favicon, no external assets |

## Local development

```bash
cd website
npm install
npm run dev        # http://localhost:5173
```

`npm run build` produces the production bundle; `npm run preview` serves it locally; `npm run deploy` builds and uploads with `wrangler`. The committed `package-lock.json` pins dependencies — install with `npm ci` on CI.

## Deploying to Cloudflare Workers

Manual deploy from any machine with Node 24:

```bash
cd website
export CLOUDFLARE_API_TOKEN=...   # token with "Workers Scripts: Edit"
export CLOUDFLARE_ACCOUNT_ID=...
npx wrangler deploy
```

CI ([`.github/workflows/website.yml`](https://github.com/shahboura/sha2lato/blob/main/.github/workflows/website.yml)) does the same on push to `main` when the repo has two secrets set:

| Secret | Value |
|---|---|
| `CLOUDFLARE_API_TOKEN` | API token with **Workers Scripts: Edit** |
| `CLOUDFLARE_ACCOUNT_ID` | your Cloudflare account id |

Without them the deploy step logs a notice and is skipped — expected on forks. The workflow triggers on `website/**`, `docs/**`, or `README.md` changes, so docs-only edits redeploy the site with fresh content.

Cloudflare Workers' free plan (100k requests/day, static assets free) comfortably covers a docs site. Custom domain: **Workers → `sha2lato-docs` → Settings → Domains & Routes** in the Cloudflare dashboard (or a `routes` entry in `wrangler.jsonc`) — no code changes.

## Adding a page

1. Write (or update) the doc in `docs/<name>.md` — it is the single source.
2. Add `website/src/<name>.mdx`:

   ```mdx
   ---
   $schema: https://holocron.so/frontmatter.json
   title: Page title
   sidebarTitle: Sidebar label
   description: One-liner for search and SEO.
   hideTitle: true
   icon: terminal
   ---

   import Doc from '../../docs/<name>.md'

   <Doc />
   ```

3. Add the slug to a group under `navigation` in `website/docs.json`.

Cross-links between docs keep working on both GitHub and the site: always link to the real file with a relative path ending in `.md`; Holocron recomputes those links per page and strips the extension.

Links from the repo `README.md` to `docs/<name>.md` cannot auto-resolve (the README lives outside the site's pages directory), so each one has a `/docs/<name>` → `/<name>` redirect in `website/docs.json`. Adding a page linked from the README means adding a matching redirect rule.

## For AI agents

Holocron serves agent-readable exports from the built site: `/llms.txt` (index), `/llms-full.txt` (all pages in one file), `/docs.zip` (raw markdown), and any page as `.md` by appending the extension — e.g. `/hosting.md`.

## Licensing

[Holocron](https://github.com/remorses/holocron) is MIT-licensed; the "Powered by Holocron" footer link is kept as the project kindly asks. Site content follows the repo license (`LICENSE`, MIT).
