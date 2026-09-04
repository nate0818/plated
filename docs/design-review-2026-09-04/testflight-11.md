# TestFlight build 11 — release record

- App version: `0.1.0 (11)`; widget extension also `0.1.0 (11)`.
- Release source: `bdc4eb4b9f04e448706eecb431e22d93745ec819`, pushed to `origin/main`.
- IPA: `build/releases/11/Plated.ipa` (ignored build artifact).
- SHA-256: `2ce406c8109cd97782a36007f3efe75a548986843bc47eed9649fe6b6dece155`.
- The archive was built in an isolated checkout at `/private/tmp/plated-testflight-11`; concurrent changes in the shared checkout cannot alter this artifact.

## Verified

Release archive and export succeeded. The exported IPA passed strict recursive signature verification using the system keychain. App and extension versions match. The app carries Production CloudKit and push entitlements, Sign in with Apple, WeatherKit, the shared app group, and `get-task-allow = false`. The built Info.plist contains `CKSharingSupported`, remote-notification background mode, and the non-exempt-encryption declaration.

Design and shared widget token gates passed. Before release, 13 preview swipe checks and 11 preview hold checks passed; signed native simulator and device builds succeeded. These are not claims of physical gesture or two-device sync verification.

## Distribution status

Apple accepted the upload with no errors at September 4, 2026, 12:07 EDT. Delivery/build UUID: `3a5649d1-1220-478f-b52c-bd6ac14f5cdb`. App Store Connect processing completed successfully (`VALID`), and build 11 is available to the Internal group (`IN_BETA_TESTING`). External state is `READY_FOR_BETA_SUBMISSION`; build 11 has not been added to External or submitted for Beta App Review because the CloudKit schema check below remains blocked. The External group continues to serve builds 2 and 10. The API response is preserved at `build/releases/11/asc-status.json`.

The en-US TestFlight test notes were published and include the gesture testing scope, pending CloudKit schema verification, and missing Instacart partner configuration. The confirmed metadata response is preserved at `build/releases/11/testflight-notes.json`.

## CloudKit access required

No CloudKit management token is configured for `cktool`; the CloudKit Console currently requires Apple Account sign-in. App Store Connect authentication and distribution signing are available, but do not grant CloudKit schema administration.

The diff from build 10 introduces these seven persisted fields:

| Persistence path | Model or record type | New field | Source type |
| --- | --- | --- | --- |
| SwiftData mirror | PlannedMeal | shoppingID | String? |
| SwiftData mirror | GroceryItem | sourcesData | Data? |
| SwiftData mirror | GroceryItem | purchasesData | Data? |
| SwiftData mirror | TableComment | parentCommentID | String? |
| SwiftData mirror | TableComment | deletedAt | Date? |
| Shared Table records | PlatedDishNote | parentCommentID | String |
| Shared Table records | PlatedDishNote | deletedAt | Date |

All model additions are optional. Verify the generated CloudKit field names and types against the Development schema, populate missing fields in Development, inspect the additive diff, and deploy it to Production in `iCloud.com.natemeadows.plated`, team `JA9M6TYXYL`. Do not reset either environment or delete existing records. The current DEBUG primers do not populate every new optional field, so running them alone is not proof that all fields exist.

After deployment, verify reply creation/deletion and grocery changes across signed-in devices, including offline replay. Then add build 11 to External with `scripts/asc distribute 11 External` and verify both its group membership and external beta state.

## Other known limits

Instacart's production partner key is still missing, so a real shopping link and checkout have not been verified. Contact-photo selection, VoiceOver, larger text, and interrupted native gestures remain physical-device checks. See `implementation-status.md` for the full design implementation scope.
