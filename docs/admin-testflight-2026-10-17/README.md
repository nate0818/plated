# Early-access request management

The founder reviews requests at `/admin/waitlist` and sends Apple TestFlight invitations directly. Launch-only subscribers are excluded. Selection is capped at ten per browser batch; each request is submitted and recorded independently, so a partial batch can be resumed without repeating confirmed invitations. Archive and restore only affect the review queue, never Apple membership.

## Trust boundaries

- Same-origin, CSRF-protected Next BFF signs requests to `admin-testflight` with the existing admin HMAC secret.
- Edge verifies the user with Auth, AAL2, a TOTP within 15 minutes, and the active founder principal. The database independently checks the founder role and permission for each RPC. Raw request emails are only returned through this protected flow.
- App Store Connect credentials stay in Supabase Edge secrets. The browser sends only stored request UUIDs; it cannot set an address, app, or beta group. Group ownership, external status, and an active external build are checked before every invite.
- `testflight_requests` has RLS enabled, no client policies, and all public/anon/authenticated table and RPC privileges revoked. Only service_role has access.
- Persistent per-request leases serialize sends across tabs. A stale lease or ambiguous Apple response requires read-only reconciliation. Checking status never creates testers, adds membership, or sends email. Unresolved ambiguity stays blocked for manual review in App Store Connect; there is no automatic resend.
- Existing invited/accepted/installed testers are recorded without another invitation. An explicit NOT_INVITED state is required before the invitation endpoint is called. Revoked testers are surfaced rather than silently re-enrolled.
- Apple responses never enter logs or audit metadata. Audit events record request UUID, action, result, and bounded provider error code, without addresses or credentials.
- Status reflects Apple's accepted operation or returned state, not confirmed inbox delivery. The first-confirmed timestamp is a console record, not historical proof of when a prior manual invite was sent.
- Deleting a waitlist row cascades its provider-tracking row. Archive preserves it. No automated invitation emails were sent during QA.

## Secrets

`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_B64`, `ASC_APP_ID`, `ASC_BETA_GROUP_ID` are required in the existing Supabase project. Reuses the existing App Store Connect key and External group; no new Apple user, role, key, or group is created.

## Validation

Unit tests cover new and existing testers, no duplicate sends, explicit NOT_INVITED handling, unknown states, network ambiguity, read-only refresh, founder authorization, request validation, exact address matching, pagination, destination checks, and ES256 JWT signing. SQL integration checks exercise archive/restore, leases, stale completion, source boundaries and RLS in a rolled-back transaction. Live provider validation is read-only.
