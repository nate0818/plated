# plated.food

The website, separate from the app. Next.js in this folder; the Vercel
project's Root Directory is `web`, so nothing above this folder is served.

- `/` is the front door with the waitlist.
- `/privacy` is the policy. Every sentence describes the running system.
- `/join` is the invitation landing page. A phone with Plated never sees it,
  because `/join` is in `public/.well-known/apple-app-site-association` and
  iOS opens the app straight from the link.
- `app/api/waitlist` writes to the `waitlist` table in the Supabase project
  `plated` with the service role. The key lives in Vercel's environment and
  in a local `.env.local`, never in the repo. See `.env.example`.

Colour tokens in `app/globals.css` are copied from `Plated/Support/Theme.swift`
by hand, light values only. Change one there, change it here.

```
npm run dev
npm run build
```
