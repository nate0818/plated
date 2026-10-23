# Notification registration correction — October 23

Production still had zero active social installations at the start of this check.
Logs included `403 cloud_identity_unavailable` at 21:40 UTC October 22, after
version 6 was deployed. The previous privacy-protected identity change did not
resolve registration; it must not be described as a verified fix.

## Contract mismatch

The server required a `users` array based on Apple's archived web-services
reference. Apple's current CloudKit JS 2 implementation of
`fetchCurrentUserIdentity` calls `public/users/caller` and returns
`httpResponse.body` directly as the caller identity. Version 7 accepts that direct
identity and the archived one-user envelope. An explicit invalid envelope,
conflicting identities, email-only identity, or absent identity still fails closed.
No client-supplied identity is trusted, and no Apple tokens or identities are logged.

References inspected:
- https://cdn.apple-cloudkit.com/ck/2/cloudkit.js
- https://developer.apple.com/documentation/cloudkitjs/cloudkit.container/fetchcurrentuseridentity
- https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/FetchCurrentUserIdentity.html

## Verification

- Backend: 26 tests passed; `deno check index.ts` passed.
- Production social v7 is ACTIVE. SHA:
  `b5756f4aedc50fce824d8144557aebe9daba657f3452b293b57d2f0789988e41`.
- Read-back index, CloudKit verification, policy, and APNs sources match the
  tested local files. The deployment API omits deno.json from source read-back.
- Unauthenticated registration returns HTTP 401 with `unauthorized`.
- Actual authenticated registration and event-to-phone delivery remain unverified.
  The response-shape mismatch is supported by Apple's SDK; an actual failing
  account response was not captured, so it is not proof of the sole live cause.

Notification settings copy is also shortened and made explicit. It no longer
promises successful in-app syncing while reporting a registration failure.
These client copy changes are not in the already-distributed build 48.
The app and widget build passed for the iOS 26.2 review simulator. A fresh
Editorial Settings render shows the revised section copy, sign-in explanation,
and visible category labels without clipping. Lower rows, alternate appearances,
Dynamic Type, and interactive sign-in/retry are not verified by that capture.
Native control tooling could not bind Simulator in this session.
This focused correction is not full approved-design or App Store readiness sign-off.
