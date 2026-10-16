# Plated App Store quality audit

Date: September 23, 2026

This is the working gap list against `DESIGN.md`. “Done” means implemented and
covered by current automated checks. It does not replace device, iCloud,
VoiceOver, or human usability evidence.

## Executive read

The app now has a recognizable visual language and a coherent core journey.
Its remaining quality risk is not a missing brand treatment. It is depth:
shared-state confidence, social audience clarity, complete edge states, and
the accumulated fit-and-finish visible when every page is used in sequence.

The highest-value work is to make Household and Table feel inevitable:
Household as the dependable private operating system for dinner, Table as the
small, intentional place where a person chooses to publish. No screen may blur
that boundary.

## Release readiness ledger

Completed in the current candidate:

- App Store version aligned to 1.0.0; required description, keywords,
  promotional text, review notes, copyright, free price and U.S.-only
  availability are saved on the unsubmitted draft.
- Five iPhone 6.9-inch and five iPad 13-inch screenshots are uploaded in
  Plan, Recipes, Groceries, Table and Household order; App Store Connect
  reports every asset complete with byte size and checksum matching the local
  release files.
- Privacy manifest and public policy describe the developer-held directory,
  notification identifiers, Table reports and local blocking.
- In-app directory deletion, Table Report/Block/Unblock controls, iPad Settings
  layout and accessibility-size Table states are implemented and covered by
  focused automated or simulator checks.
- The Table moderation runbook now defines 24-hour acknowledgement, severity,
  containment, privacy and escalation boundaries; its production two-account
  drill is still required.
- On September 24, `PlatedHouseholdGroceryLine.recipeOriginsJSON` was added as
  a String field and deployed to Production. CloudKit Console confirmed the
  deployment and showed the field in Production; all 154 schema entries now
  pass the local release gate.
- The corresponding private SwiftData mirror field,
  `CD_GroceryItem.CD_recipeOriginsData` (Bytes), was also deployed and verified
  in Production. The local gate does not scan persisted-model fields.
- Signed 1.0.0 (30) archive/export, strict app/widget signature verification,
  Production entitlements, and upload succeeded. Build 30 was added to
  External, then expired on September 24 after the navigation freeze was
  reproduced. It is no longer installable. See `docs/testflight-30.md`.
- Profile-to-Household navigation was subsequently reproduced as a render
  loop. Hotfix 1.0.1 (31) adds stable destination identities and deleted-seat
  guards, passes 368 tests and nested navigation/editing checks, and has been
  signed, uploaded, and processed. It is available internally and submitted for
  external beta review; see
  `docs/testflight-31.md`. Build 29 remains the latest approved external build
  until Apple approves 31. Build 30 should not be the App Store candidate.

Still release-blocking:

- publish the current privacy policy to `plated.food/privacy` and verify the
  production response; the current public deployment predates these release
  changes;
- deploy the directory-deletion migration/function and complete automatic Sign
  in with Apple token exchange/revocation with production secrets;
- enter and publish the four App Privacy data types mapped in
  `docs/app-store-privacy-disclosures.md`, then complete account-agreement
  review in the App Store Connect UI;
- select a verified crash-fixed build, aligning its marketing version with the
  App Store draft, once the remaining submission prerequisites are satisfied;
- complete the physical-device, VoiceOver, permissions and two-account matrix
  below.

No build has been selected for the App Store draft and no App Store review
submission has been created. TestFlight Beta App Review for build 31 is separate.

Automated candidate evidence captured September 23, 2026:

- 366 of 366 XCTest cases passed on a freshly erased iPhone 17 Pro simulator,
  including all content-safety and directory-deletion regressions;
- `git diff --check`, the design contract check, and the shared-token check
  passed;
- the Release analyzer completed without findings;
- all six directory-deletion Edge Function tests passed, and the website
  completed ESLint, TypeScript and optimized Next.js production builds;
- a fresh unsigned generic Release archive completed for app and widget at
  version 1.0.0 (24), with matching dSYMs and plist-valid packaged privacy
  manifests;
- the schema gate failed for exactly one intentionally unaccepted production
  field: `write.recipeOriginsJSON`.

The unsigned archive is not distribution evidence. A September 24 check outside
the sandbox confirmed valid Apple Development and Apple Distribution identities;
the earlier sandbox-only identity result was misleading. Signed release evidence
is recorded separately for the TestFlight candidate.

## Quality priorities

| Priority | Gap | Status | Exit evidence |
|---|---|---|---|
| P0 | Root tray follows focused/profile/admin pages and covers their content | Implemented | Native Profile, Household, recipe, thread, Activity, and Settings captures |
| P0 | Household and Table terminology, audience, and ownership can drift | Contract added; code audit continues | Two-account task matrix and copy inventory |
| P0 | Shared workflows are primarily simulator-tested | Open | Two real iCloud accounts complete the collaboration matrix |
| P0 | Permission, offline, partial-sync, and revocation states lack one release matrix | Open | State screenshots plus recovery task results |
| P0 | Table abuse handling still depends on a support email and client-local blocks | Client controls and support runbook implemented; live drill open | Report receipt and two-account abuse drill within the documented response target |
| P0 | Sign in with Apple authorization is not revoked programmatically on account deletion | Directory deletion and manual Apple-account fallback implemented; server token exchange is open | Install Apple server secrets, exchange and encrypt refresh tokens, revoke live, then complete the deletion matrix |
| P1 | Root utility anatomy differs by tab | Implemented | Bell and profile appear consistently on four root screens |
| P1 | Table trust preamble pushes the first post too far below the fold | Implemented | Native populated Table capture |
| P1 | Self profile puts awards before the living household relationship | Implemented | Native populated and empty Profile captures |
| P1 | Household puts stats before people and current coordination | Implemented | Native one-person, invited, and full-household captures |
| P1 | Empty household banner reserves the height of missing content | Implemented | Native no-banner Household capture |
| P1 | Settings is visually dense and needs full state-by-state inspection | Simulator AX5/iPad pass complete; device permission states open | Permission states at default, AX3, and AX5 on a physical device |
| P1 | Grocery export action can visually outrank the act of shopping | Open | In-store usability pass and revised action hierarchy if confirmed |
| P2 | Spacing values remain locally authored across many views | Open | Shared rhythm tokens adopted when each page is touched |
| P2 | Motion and haptic vocabulary needs device-level review | Open | Reduce Motion and physical-device gesture run |

## Page scorecard

### Plan

Current strengths: selected night is unmistakable, week/month relationship is
clear, the dinner photo carries emotion, and Cook is a direct action.

Next bar:

- prove open, partial, deleted, moved, reassigned, cooked, and offline nights;
- make the next unresolved night visible without competing with tonight;
- verify drag, edge scroll, menus, and VoiceOver alternatives on a device;
- ensure every route returns to the same date and scroll context.

### Recipes

Current strengths: strong photo grid, visible search, compact filtering, clear
favorite state, and ownership/source copy.

Next bar:

- verify imported drafts from URL, scan, photo, share extension, and manual;
- audit long titles, missing photos, multiple sources, household edits, and
  active-cook snapshot behavior;
- keep source attribution visible without turning tiles into metadata cards;
- validate creator, household editor, and read-only action menus separately.

### Groceries

Current strengths: shopping window is explicit, meal scope is selectable,
pantry assumptions are reversible, and every generated line keeps provenance.

Next bar:

- test the list while walking and using one hand;
- confirm checking remains the dominant action over Reminders or Instacart;
- validate duplicate ingredient math, recipe rename, household changes,
  manual extras, all-checked, empty-plan, and offline rebuild states;
- verify units and quantities at accessibility sizes and in localization.

### Table

Current strengths: private audience is explicit, identity mutations are
authorized, drafts and outboxes survive network failure, and reaction counts
do not shame an empty post. Other people's posts and comments have independent
Report and Block actions; blocked authors disappear locally and can be restored
from People.

Next bar:

- test composer destination, People, post card, thread, activity, and profile
  as one continuous journey;
- prove duplicate names, rename, revoked seat, failed delete, retry, and
  notification deep links with two accounts;
- prove the support inbox can identify, acknowledge, investigate, and resolve a
  report without receiving private text or photos by default;
- add server-backed enforcement before claiming that a local block revokes a
  person's access or removes content for anyone else;
- review photo aspect ratios, long captions, URL-only comments, polls, and
  rapid reactions;
- keep the first human post visible early in the first viewport.

### Profile

Current strengths: person-first navigation, stable identity where available,
clear self/other actions, and contribution tabs.

Next bar:

- replace every remaining name fallback with stable identity as data permits;
- verify empty profiles do not look unfinished;
- test long names, bios, no photo, one award, many awards, and no household;
- ensure Household and Settings feel like destinations, not utility rows.

### Household

Current strengths: real invitation states, organizer terminology, honest
iCloud copy, role/removal handling, and a visible cook rotation.

Next bar:

- run host, member, invited, removed, left, offline, and partial-import views;
- make current coordination more prominent than historical achievement;
- prove every organizer-only control disappears or explains itself for members;
- validate pending edits, convergence, revocation, rename, and two people with
  the same display name on physical devices.

### Settings

Current strengths: controls are grouped by outcome and denied permissions lead
to a resolution instead of becoming inert switches.

Next bar:

- capture every permission state and the return from iOS Settings;
- verify appearance, reminder, calendar, sync, sign-out, leave, and account
  actions with long copy and AX5;
- remove any explanation that repeats a control rather than clarifying impact;
- verify directory deletion removes server data and local credentials while
  leaving private iCloud content untouched;
- complete and live-test the programmatic Sign in with Apple revocation path in
  `docs/sign-in-with-apple-deletion.md` before release.

### Onboarding and Cook Mode

Next bar:

- test interrupted onboarding, skipped identity, delayed permissions, invite
  cold launch, and returning-user launch;
- test Cook Mode with timers, screen lock, app termination, recipe edits,
  minimized resume, End, and notification deep links;
- validate both with VoiceOver and Reduce Motion on a physical phone.

## Release-blocking collaboration matrix

The following must pass with two real Apple/iCloud accounts:

1. Organizer creates and names a household.
2. Organizer sends an invitation; the app records sent only after handoff.
3. Member previews the correct organizer and shared scope, then accepts.
4. Both devices converge on roster, Plan, Recipes, and Groceries.
5. Each device edits a different object offline, reconnects, and converges.
6. Both edit the same plan night; the result is deterministic and explained.
7. Organizer changes a role and removes a member.
8. Removed member loses shared access without losing unrelated local content.
9. Table invitation, post, comment, reaction, edit, delete, and notification
   deep links work in both directions.
10. Rename and duplicate display names do not change authorship or authority.

No amount of screenshot polish substitutes for this matrix. This is where the
product earns trust.
