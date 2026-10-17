# plated.food

The website, separate from the app. Next.js in this folder; the Vercel
project's Root Directory is `web`, so nothing above this folder is served.

- `/` introduces the app with real screenshots, an interactive feature tour,
  and household and Table stories. Marketing CTAs point to `/early-access`.
- `/early-access` collects one email for a reviewed invitation. It explains that
  invitations go out in batches and that invited people install through TestFlight.
- `/privacy` is the policy. Every sentence describes the running system.
- `/join` is the invitation landing page. A phone with Plated never sees it,
  because `/join` is in `public/.well-known/apple-app-site-association` and
  iOS opens the app straight from the link.
- `app/api/waitlist` forwards to the `waitlist` edge function in the Supabase
  project `plated`, which stores the request with the service role on Supabase's
  side. Early-access requests use `plated.food/early-access`; launch-only
  signups retain `plated.food`. An existing launch subscriber who requests access
  is upgraded without creating a duplicate. The public browser receives only the publishable key, which can read
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
pages. The optional paper palette remains available for explicit light surfaces. Change a native
token there, change its web counterpart here; `make tokens` verifies both palettes. The homepage uses Newsreader
titles, DM Sans reading text, fine rules, flat surfaces, small rectangular
controls, and orange primary actions. The hero is an 18-second recording of the
actual app in Light appearance, starting on Plan at 8:18 before opening Recipes.
The poster uses Next’s image optimizer instead of downloading the raw capture.
Playback stops offscreen and in background tabs; autoplay also respects Data Saver. A visible Play/Pause control
remains available; Reduced Motion keeps the Plan poster until Play is chosen.
The masthead and footer use the Newsreader wordmark alone. The approved native
P artwork is used for browser and touch icons.

The recipe section uses an original, layered composition of existing food
photographs. Its copy focuses on adding your recipes and saving dishes friends
share at your Table. It makes no claim that a cookbook comes preloaded.
On desktop, the walkthrough keeps its phone and step navigation sticky while
Plan, Recipes and Groceries copy scrolls on the right. IntersectionObserver
selects the matching screen. The remaining screens load ahead once the desktop tour comes into view.
Hidden desktop captures stay lazy on mobile. On mobile, each story has its own inline app capture.
The Plan preview uses a real capture of Sam’s assigned Pizza Night. The native
avatar and “Sam is cooking” label carry the collaboration story. Beneath the Plan
description, a static, staggered group of household initials pairs each cook
with a meal-photo badge and their assigned dinner. It is a decorative example,
with no avatar controls or separate table. Step numbers use cream for high contrast. The Table
phone sits directly on the canvas.
App stills can be enlarged in native dialogs, with arrow-key navigation and
Escape to close. Navigation remains usable with a keyboard and Reduced Motion.

The current implementation and verification notes are in
`../docs/website-product-story-2026-10-16/README.md`. Earlier design explorations
remain in their dated folders. Request capture is separate from invitation delivery. The founder console
keeps addresses masked in its list, shows request purpose, and offers founder-only
CSV downloads in batches of 100 after fresh MFA. Exports are audited and contain
only early-access requests. Review the downloaded addresses and add selected
people to an external testing group in App Store Connect; Apple sends invitations
there. Downloading does not send messages or grant access.

The footer includes Apple's unmodified App Store badge, explicitly marked as
coming soon and unlinked while the configured listing returns 404. Invited people continue to install through TestFlight. Set the badge's `available` prop only after the
listing is published and verified. Homepage depth and short entrance motion are
scoped to marketing artwork; the native app's flat surface rules are unchanged.

Fonts in `app/fonts` are the same variable TTFs shipped with the native app,
self-hosted through `next/font/local`. Homepage imagery and its source captures
are documented in `public/app/README.md` and `public/editorial/README.md`.

Regenerate browser icons and the social card after a brand or screenshot change
with `node scripts/generate-editorial-artwork.cjs`. It uses the bundled fonts,
current CSS palette, the native P artwork, and the actual Light Plan capture. Font licenses are
stored beside the binaries.

```
npm run dev
npm run build
```

Mobile refinement: the hero copy renders immediately; phone entry takes 450ms,
the food composition opens once over 550ms, and tour changes fade over 200ms.
Reduced Motion disables decorative movement and keeps the video poster until
Play is chosen. All mobile walkthrough and Table previews share a 264px frame,
and avatar meal/day labels use separate lines. Email fields use 16px text to
avoid focus zoom on iOS.
