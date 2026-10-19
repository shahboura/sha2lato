/**
 * sha2lato docs site — Holocron + Cloudflare Workers.
 *
 * Content lives in the repo's README.md and docs/*.md; src/ holds thin MDX
 * wrappers that import them (see website/src/*.mdx). Deploy: docs/website.md.
 */
import { cloudflare } from '@cloudflare/vite-plugin'
import { holocron } from '@holocron.so/vite'
import { defineConfig } from 'vite'

export default defineConfig({
  // The Cloudflare plugin's prerender step starts `vite preview` and dials it
  // over loopback; bind IPv4 explicitly so hosts that resolve `localhost` to
  // `::1` first (some containers) can't ECONNREFUSED the prerender fetch.
  preview: { host: '127.0.0.1' },
  plugins: [
    holocron({ pagesDir: './src' }),
    cloudflare({
      viteEnvironment: {
        name: 'rsc',
        childEnvironments: ['ssr'],
      },
    }),
  ],
})
