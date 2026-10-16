# plated.food

The website, separate from the app. Next.js in this folder; the Vercel
project's Root Directory is `web`, so nothing above this folder is served.

- `/` introduces the app with real screenshots, an interactive feature tour,
  and household and Table stories. Early access points to the shared TestFlight
  URL in `app/lib/store.ts`; the waitlist is for the App Store launch.
- `/privacy` is the policy. Every sentence describes the running system.
- `/join` is the invitation landing page. A phone with Plated never sees it,
  because `/join` is in `public/.well-known/apple-app-site-association` and
  iOS opens the app straight from the link.
- `app/api/waitlist` forwards to the `waitlist` edge function in the Supabase
  project `plated`, which does the insert with the service role on Supabase's
  side. The public browser receives only the publishable key, which can read
  nothing on its own.
- `/admin` is the private founder console. Supabase Auth supplies the
  invite-only account and requires a TOTP authenticator for every console
  session. Each read and command goes through a Next.js BFF, which verifies
  the signed session and AAL2 again, restricts the operation and payload, then
  forwards the user JWT to a narrow Edge Function. The Edge Function checks
  the active `admin_principals` row and permission before using service-role
  access. No Supabase service-role key or Supabase secret key belongs in
  Vercel or the browser.

The founder console needs these Vercel environment variables:

```
NEXT_PUBLIC_SUPABASE_URL=https://<project-ref>.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
ADMIN_ORIGIN=https://plated.food
ADMIN_API_SECRET=<same high-entropy value configured on Supabase Edge Functions>
```

`ADMIN_API_SECRET` and `ADMIN_ORIGIN` must be scoped to the Production
environment in Vercel and must not be made available to Preview deployments.
Production admin requests fail closed when `ADMIN_ORIGIN` is absent or the
request arrives on another host.

`ADMIN_READ_FUNCTION_URL` and `ADMIN_COMMAND_FUNCTION_URL` are optional. When
set, they must still point to `/functions/v1/admin-read` and
`/functions/v1/announce` on the configured Supabase origin. Invite the founder
through Supabase Auth, insert that Auth user into `admin_principals`, associate
`directory_user_id` for the “My devices” audience, and enroll TOTP on the first
console sign-in. Configure Supabase's invite template to link to
`https://plated.food/admin/auth/confirm?token_hash={{ .TokenHash }}&type=invite`
and its recovery template to link to
`https://plated.food/admin/auth/confirm?token_hash={{ .TokenHash }}&type=recovery`.
The console exchanges that token only on `ADMIN_ORIGIN`, prompts for a password
of at least 14 characters, then requires TOTP. Reading the console requires
AAL2; every founder command requires a TOTP verification from the last 15
minutes.

Colour tokens in `app/globals.css` mirror the Editorial system in
`Plated/Support/Theme.swift`: deep green by default across public pages, the private console, and error
pages. The optional paper palette is retained for explicit future use. Change a native
token there, change its web counterpart here; `make tokens` verifies both palettes. The homepage uses Newsreader
titles, DM Sans reading text, fine rules, flat surfaces, small rectangular
controls, and orange primary actions. The homepage pairs shared-table brand
photography with actual app captures. The app preview uses a native dialog,
named screen buttons, arrow-key navigation, and Escape to close.

Fonts in `app/fonts` are the same variable TTFs shipped with the native app,
self-hosted through `next/font/local`. Homepage imagery and its source captures
are documented in `public/app/README.md` and `public/editorial/README.md`.

Regenerate browser icons and the social card after a brand or screenshot change
with `node scripts/generate-editorial-artwork.cjs`. It uses the bundled fonts,
current CSS palette, and the actual Editorial Plan capture. Font licenses are
stored beside the binaries.

```
npm run dev
npm run build
```
