# sha2lato website

Documentation site for sha2lato — [Holocron](https://holocron.so) (Vite plugin) deployed to Cloudflare Workers.

The pages in `src/` are thin wrappers: each imports the real markdown from `../README.md` or `../docs/*.md`, so GitHub, Forgejo, and the site all render one source. **Docs content lives in `docs/`, never here.**

## Commands

| Command | What it does |
|---|---|
| `npm install` | install dependencies (lockfile is committed) |
| `npm run dev` | dev server at http://localhost:5173 |
| `npm run build` | production build (worker + assets) |
| `npm run preview` | serve the production build locally |
| `npm run deploy` | build + `wrangler deploy` (needs `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID`) |

## Layout

- `docs.json` — site name, colors, fonts, navigation (groups + page slugs)
- `global.css` — theme tokens; Holocron picks it up automatically from the project root
- `src/*.mdx` — one wrapper per page (frontmatter + `import Doc from '../../docs/<name>.md'`)
- `wrangler.jsonc` — worker config (`sha2lato-docs`)
- `public/` — SVG logo (light/dark) + favicon

See [docs/website.md](../docs/website.md) for deploys, CI secrets, free-tier notes, and how to add a page.
