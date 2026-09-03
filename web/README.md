# plated.food

The website, separate from the app. Next.js in this folder; the Vercel
project's Root Directory is `web`, so nothing above this folder is served.

- `/` is the front door with the waitlist.
- `/privacy` is the policy. Every sentence describes the running system.
- `/join` is the invitation landing page. A phone with Plated never sees it,
  because `/join` is in `public/.well-known/apple-app-site-association` and
  iOS opens the app straight from the link.
- `app/api/waitlist` forwards to the `waitlist` edge function in the Supabase
  project `plated`, which does the insert with the service role on Supabase's
  side. The website holds no secrets: only the publishable key, which can
  read nothing.

Colour tokens in `app/globals.css` are copied from `Plated/Support/Theme.swift`
by hand, light values only. Change one there, change it here.

```
npm run dev
npm run build
```
