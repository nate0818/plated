# Sign in with Apple account deletion

Date: September 23, 2026

## Current boundary

Plated's developer-side account is the directory record. The in-app Settings
action authenticates with the private directory bearer and deletes that record,
associated invitations, devices, directory sessions, personal announcement
delivery rows, and server-side Instacart handoff state in one database
transaction. It then clears the local Apple identifier, directory bearer, and
account-scoped Table blocks.

Recipes, plans, grocery lists, household records, Table posts, comments, photos,
and cooking history are private or participant-shared CloudKit records. They are
not held in the developer's account database and the service role cannot read or
delete them. The deletion confirmation says this explicitly. Users can delete
their own posts in Plated and can remove all synced Plated content from iCloud
storage separately; directory deletion never silently destroys either their
private content or copies already shared with other iCloud participants.

The current build does not possess an Apple refresh token. It therefore cannot
call Apple's token-revocation endpoint. After the directory transaction succeeds,
the app gives the manual fallback for this legacy state: Settings, the user's
name, Sign in with Apple, Plated, Delete. The confirmation explains that path,
and a successful deletion opens `https://account.apple.com` for the web route.
Account-data deletion still
completes if Apple authorization has not yet been revoked.

## Release blocker: automatic token revocation

Do not describe the account-deletion flow as complete for release until the
following server work is deployed and verified with a real test Apple Account.
Apple expects apps with server-backed Sign in with Apple accounts to validate
the authorization code, retain a revocable token securely, and revoke it when
the account is deleted.

### Apple Developer setup

1. Confirm the primary App ID `com.natemeadows.plated` has Sign in with Apple
   enabled for the production Apple Developer team.
2. Create a dedicated Sign in with Apple private key. Record its Key ID and
   Team ID and download the `.p8` file once. Never add the file to this repo.
3. Install these values as Supabase Edge Function secrets, not database rows or
   client configuration:
   - `APPLE_CLIENT_ID=com.natemeadows.plated`
   - `APPLE_TEAM_ID`
   - `APPLE_KEY_ID`
   - `APPLE_PRIVATE_KEY_P8` (preserve the PEM exactly, or base64-decode it only
     inside the function)
   - `APPLE_TOKEN_ENCRYPTION_KEY` (a separate random 32-byte AES key, versioned
     so ciphertext can be rotated)
4. Restrict production secret access to the account-authentication and
   account-deletion functions. The Apple key and encryption key must never be
   returned, logged, placed in `NEXT_PUBLIC_*`, or shipped in the app.

### Registration contract

1. Read both `identityToken` and `authorizationCode` from
   `ASAuthorizationAppleIDCredential` and send them over TLS in the same
   registration attempt. The authorization code is single-use and short-lived;
   never persist it on the device or retry it after Apple has consumed it.
2. Restore the deployed `/register` implementation to source control before
   changing it. Its current production source is missing from this repository,
   so modifying the protocol blind is not safe.
3. On the server, verify the identity-token signature, issuer, audience,
   expiration, and nonce/state contract. Exchange the authorization code at
   `https://appleid.apple.com/auth/token` using a short-lived ES256 client-secret
   JWT signed by the dedicated Apple `.p8` key.
4. Verify that the returned ID token's subject matches the directory
   `apple_user_id`. Reject registration on any mismatch.
5. Encrypt the returned refresh token with AES-256-GCM using a fresh random
   nonce and authenticated data containing the directory user UUID, client ID,
   and encryption-key version. Store only ciphertext, nonce, tag/key version,
   and timestamps in a service-role-only table with RLS enabled and no browser
   policies. A hash alone is insufficient because revocation needs the token.
6. Never store authorization codes or Apple client-secret JWTs. Do not log any
   token or token-exchange body.

### Deletion contract

1. Resolve and lock the authenticated directory account exactly as
   `delete_directory_account` does today.
2. Decrypt the refresh token only in the deletion function and submit it to
   `https://appleid.apple.com/auth/revoke` with `client_id`, a freshly minted
   client-secret JWT, and `token_type_hint=refresh_token`.
3. Treat Apple's HTTP 200 as success whether the token was newly revoked or was
   already invalid. Redact all token values from errors and logs.
4. After revocation, run the existing atomic directory deletion and delete the
   encrypted refresh-token row in the same data transaction. For a legacy row
   that has no refresh token, do not deny data deletion: retain the manual Apple
   Account instruction and record a non-sensitive operational metric so the
   fallback population can be retired.
5. Keep the idempotency receipt. A lost HTTP response must be safely retryable
   without recreating an account or exposing whether a bearer ever existed.

### Required release evidence

- A new account exchanges a fresh authorization code exactly once and stores
  decryptable ciphertext, never plaintext.
- Wrong audience, subject, signature, expired code, reused code, wrong key
  version, corrupt ciphertext, and Apple 4xx/5xx responses all fail closed.
- A successful deletion receives HTTP 200 from Apple, removes every directory
  row covered by the SQL migration, clears the local Keychain, and causes
  `ASAuthorizationAppleIDProvider.credentialState` to settle to revoked or not
  found.
- Repeating the same deletion request returns success from the idempotency
  receipt without needing the deleted directory row.
- A legacy account with no refresh token still loses all developer-held data
  and sees the exact manual revocation path.
- Supabase database advisors, Edge Function tests, the two-account deletion
  matrix, and production logs with token redaction all pass before submission.

No secret installation, migration application, function deployment, or live
Apple-account mutation is performed by the repository change alone.

## Apple references

- [Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app)
- [TN3194: Handling account deletions and revoking tokens for Sign in with Apple](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
- [Token revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens)
- [Manage apps that use Sign in with Apple](https://support.apple.com/102571)
