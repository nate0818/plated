# Founder console

The founder console at `/admin` is Plated's operational control plane. It
answers whether the public services are healthy, who can receive a service
message, and what the service has done. It does not copy the private product
into a second database.

## Privacy boundary

Recipes, meal plans, grocery lists, households, photographs, Table posts and
cooking history remain in each household's private CloudKit data. The console
cannot query or display them. Plated also has no app analytics, crash reporter,
subscription ledger or support-ticket database today. The console names those
as coverage gaps until a real source is connected and the public privacy policy
describes it.

The operational database may expose only redacted projections to an
authenticated admin. It must never return Apple subject identifiers, directory
API tokens, phone hashes, APNs tokens or invitation links to the browser.
Waitlist addresses are masked by default.

## Access model

The console uses a Supabase Auth account that is separate from the consumer
app's Sign in with Apple directory identity. Access requires all of the
following on every data request and command:

1. A valid Supabase user session.
2. A verified TOTP factor (`aal2`).
3. An active row in `admin_principals` with the requested permission.
4. A request sent through the Next.js backend, signed over the exact method,
   path and body with `ADMIN_API_SECRET`.

Privileged reads accept an existing AAL2 session. Previewing or executing an
announcement command requires a TOTP verification from the last 15 minutes.
The command endpoint checks this again even if the browser UI is bypassed.

The browser never receives a Supabase service or secret key, the APNs signing
key, or `ADMIN_API_SECRET`. Deactivating the principal revokes console access
without changing the person's consumer account. Admin pages are private,
uncacheable, excluded from indexing and excluded from website analytics.

## What is in the first release

- **Overview** shows directory accounts, notification-eligible devices,
  waitlist size, recent invitations, delivery health and setup blockers.
- **People** shows safe account and device metadata: display name, joined and
  last-registration times, whether a phone number is on file, device count,
  app version/build, release channel, APNs environment, notification setting
  and last device check-in.
- **Waitlist** shows totals and masked recent addresses. Revealing or exporting
  addresses is deliberately outside the first release.
- **Announcements** previews an exact recipient snapshot, requires the title to
  be typed before sending, records each device attempt, resumes retryable
  failures and supports a correction linked to the original announcement.
- **Operations** shows database/configuration readiness, device metadata
  coverage, recent failures and direct links to the external systems that own
  the rest of the truth.
- **Audit** records successful privileged reads, previews, queues, retries and
  retractions with a verified actor and sanitized metadata, plus automated
  retention events.

An APNs `200` means Apple accepted the notification. It does not prove the
person saw it. The console uses “accepted by Apple” rather than “delivered.”

## Announcement safety

Previewing creates a short-lived action intent and snapshots eligible devices
into `announcement_deliveries`. Sending consumes that one intent atomically;
the content or audience cannot change between preview and execution. Fleet
rate limits and one-build rules are claimed inside the database under a lock,
so concurrent requests cannot both pass.

Delivery is bounded and resumable. Each device is pending, sending, accepted,
retryable, or permanently failed. A worker can reclaim attempts stranded by a
timeout. Only authoritative permanent APNs token errors remove a token;
timeouts, throttling and provider failures remain retryable. Retries use the
same APNs collapse identifier, which bounds duplicate visible notices if Apple
accepted a request just before a worker lost its database connection.

Release channel and APNs environment are separate fields. TestFlight and App
Store both use production APNs, so an audience must use the recorded release
channel rather than guessing from the gateway.

## What is deployed, as of 2026-09-08

The console reads a live database while the shipped app still authenticates
with `api_token`. That is deliberate, and it is why the cutover in
`20260905_announcements.sql` is gated on `directory_cutover_enabled()`.

Applied to the `plated` project, as four migrations named
`founder_console_*`: the device metadata columns, `directory_sessions`, the
nullable `device_tokens.directory_session_id`, `admin_principals`,
`announcements`, `admin_action_intents`, `announcement_deliveries`,
`admin_audit_events` with its append-only trigger, `admin_permission_allowed`,
`admin_record_audit_event`, `admin_read_metrics`, `purge_admin_ephemera`, and
the RLS and service-role grants. `public._backup_device_tokens_20260908` holds
the rows as they were before any of it.

Not applied, and not needed until the app ships the session protocol: the
directory session RPCs, `upsert_device_token`, `record_invite_attempt`, and
every announcement send RPC. Their grants come with them. Applying the whole
file with the flag on completes the cutover, and it is idempotent, so it is
also the way to finish this.

Deployed: `admin-read`, with `verify_jwt` on. `register`, `lookup`, `device`
and `invite` are untouched and still speak the old protocol.

So the console reads truthfully today and cannot send. An announcement needs a
live directory session per device, and no device has one yet, so a preview
would honestly name zero people. `_shared/apns.ts` exists twice, here and as
`invite/apns.ts`, until the cutover retires the second copy.

The app-side rewrite that ends this state lives on `codex/founder-admin` and is
deliberately not on `main`: a phone built from it would speak a protocol the
server has not cut over to.

## Configuration and bootstrap

The website needs these Vercel environment variables:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
ADMIN_ORIGIN=https://plated.food
ADMIN_API_SECRET
```

`ADMIN_ORIGIN` and `ADMIN_API_SECRET` must be scoped to Production in Vercel,
never Preview. Production requests on any other host fail before an invite or
recovery token is consumed or a command is accepted.

The `admin-read` and `announce` Edge Functions need the same
`ADMIN_API_SECRET`. They use Supabase's server-only secret key (with the legacy
service-role key accepted during key migration). `announce` also needs:

```text
APNS_TEAM_ID
APNS_KEY_ID
APNS_KEY_P8
```

Bootstrap is intentionally manual:

1. Apply the device and founder-console migrations.
2. Invite the founder email from Supabase Auth. Public signup stays disabled.
3. Insert that Auth user's UUID into `admin_principals` with the founder role
   and permissions listed by the migration.
4. Deploy `device`, `invite`, `admin-read` and `announce` with the authentication
   settings documented beside the functions.
5. Set the website variables and deploy the web app.
6. Sign in at `/admin/login`, enroll a TOTP authenticator and verify that the
   session reaches `aal2`.
7. Register one development phone and one TestFlight phone, then preview a
   founder-only announcement before any fleet send.

No fleet notification is part of setup. A real send is a separate founder
action after the preview names the exact reach.

## Recovery

- **Lost authenticator:** recover the Supabase Auth account from the dashboard,
  revoke its factors and require a fresh enrollment. Do not add an MFA bypass.
- **Suspected browser session:** deactivate the principal, revoke Auth sessions,
  then rotate `ADMIN_API_SECRET` on both Vercel and Supabase before reactivating.
- **Interrupted announcement:** use Retry in the announcement detail. It claims
  only pending, retryable or stale-sending rows.
- **Wrong copy already accepted:** retract the record for bookkeeping and send a
  linked correction to the same cohort. Retraction cannot erase a banner that a
  phone already received.
- **APNs key rotation:** update the three APNs secrets together, preview founder
  reach, and send only to the founder cohort as the verification step.

## Next data sources

App Store Connect build state is the next useful integration because it can
prove a build is available before a build notice is enabled. Vercel deployment
health, GitHub checks, privacy-preserving crash reports and a support inbox can
follow. Revenue, retention and feature funnels require both a real collection
system and a product/privacy decision; they are not inferred from directory
registrations.
