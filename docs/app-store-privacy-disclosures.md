# App Store privacy disclosures for Plated 1.0.1

Updated: October 18, 2026 — build 41

This is an implementation audit and App Store Connect entry checklist, not
legal advice. The Account Holder, Admin or App Manager publishing the answers
must verify them against the production services and obtain qualified privacy
or legal review where required.

## Summary

**Proceed with conditions.** For the current 1.0.1 binary, answer **Yes, we
collect data from this app**, then declare these eight types:

| App Store category | Data type | Purpose | Linked to the user | Used for tracking |
|---|---|---|---|---|
| Contact Info | Name | App Functionality | Yes | No |
| Contact Info | Phone Number | App Functionality | Yes | No |
| Identifiers | User ID | App Functionality | Yes | No |
| Identifiers | Device ID | App Functionality | Yes | No |
| Contacts | Contacts (shared-room membership) | App Functionality | Yes | No |
| User Content | Other User Content | App Functionality | Yes | No |
| Usage Data | Product Interaction (comments, reactions, joins) | App Functionality | Yes | No |
| Other Data | Other Data Types (delivery settings and metadata) | App Functionality | Yes | No |

These selections match `Plated/PrivacyInfo.xcprivacy`. No advertising,
marketing, analytics, personalization, or tracking purpose is selected.

Apple defines collection as transmitting data off the device in a form the
developer or a partner can access for longer than is necessary to service the
request in real time. Apple also says on-device-only data is not collected and
that developers are not responsible for data Apple itself collects through
Apple services. See [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
and [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy).

## Why each type is declared

### Name — linked, App Functionality, not tracking

The directory stores the first/display name used for invitations and directory
membership. Invitation metadata can also retain the inviter's first name for
the documented abuse-limit and troubleshooting period.

### Phone Number — linked, App Functionality, not tracking

The directory stores salted hashes of phone numbers for contact matching and
invitation delivery/abuse limits. Apple's definition of Phone Number expressly
includes hashed phone numbers. Raw address-book numbers sent for a lookup are
hashed and compared in the real-time request and are not retained, but the
persisted hashes still make this disclosure required.

### User ID — linked, App Functionality, not tracking

The directory validates Sign in with Apple and stores an Apple-backed account
identifier plus private directory/session identifiers. They authenticate the
directory, invitation, device-registration and account-deletion functions.

### Device ID — linked, App Functionality, not tracking

The directory stores the opaque APNs token associated with the signed-in
directory account so Plated can deliver invitation, shared-activity and rare service notices.
It is a device-level identifier under Apple's category definition.

## Shared activity additions in build 41

The service retains selected comment excerpts, post titles, reactions, join events,
room membership IDs, delivery settings and status for App Functionality. These map
to Other User Content, Product Interaction, Contacts (Apple includes social graph),
and Other Data Types respectively. Identifiers remain linked and are never used
for tracking. Event payloads/status expire within three days; deduplication IDs
within eight days. Device bindings/preferences last until revoked or deleted.

The bundled manifest is updated. App Store Connect labels must be updated before
public App Store release; editing this file does not publish those answers.
Definitions: [Apple collected data types](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype).

## Data intentionally not selected for 1.0.1

| Data or feature | Why it is not another App Store data type in this binary |
|---|---|
| Recipes, plans, grocery lists and photos | Stored in private/shared CloudKit. The notification service does not fetch recipe contents or photo assets. |
| Location and weather | Location is used for a WeatherKit request and local meal matching. Plated does not retain or receive it on a developer server; Apple says developers do not declare data collected by Apple. |
| Calendar and Reminders | Read/written through local Apple frameworks for the feature the person invokes; no developer server receives the events, calendars, reminders or grocery lines. |
| Address-book contents | Contact selection and suggestions are local; lookup phone numbers are not retained. Contacts is now declared for retained shared-room membership, not an uploaded address book. |
| Recipe-import URL | The phone makes the user-requested real-time request to the chosen website. Plated does not retain browsing history on a developer server. |
| Table report email | The app opens the person's mail composer with a selected reason and opaque references. It sends nothing automatically. An infrequent, optional support request affirmatively sent by the person meets Apple's optional-disclosure framework; the prepared message excludes content, names and photos. |
| Instacart grocery handoff | `InstacartService.isOffered` is `false` in 1.0.0, so the UI cannot transmit grocery lines. Do not enable it without adding the partner to the policy and re-evaluating Other User Content and partner collection. |
| Analytics, diagnostics and advertising | The app contains no analytics, ads, advertising SDK, third-party tracking SDK or developer crash-reporting service. Apple's own App Store analytics are Apple's collection. |

## App Store Connect entry procedure

Required role: Account Holder, Admin or App Manager.

1. Open **My Apps › Plated › App Privacy**.
2. Confirm the Privacy Policy URL is `https://plated.food/privacy`. Do not
   publish until that URL serves the October 18, 2026 policy.
3. Optionally set the User Privacy Choices URL to the same page; it contains
   the in-app directory-deletion and iCloud-deletion paths.
4. Choose **Get Started** and **Yes, we collect data from this app**.
5. Select **Contact Info › Name**, **Contact Info › Phone Number**,
   **Identifiers › User ID**, **Identifiers › Device ID**, **Contacts**,
   **User Content › Other User Content**, **Usage Data › Product Interaction**,
   and **Other Data Types**.
6. Open each of the eight types and select only:
   - **App Functionality** as the purpose;
   - **Yes**, the data is linked to the user's identity;
   - **No**, the data is not used for tracking.
7. Check the Product Page Preview. It should say **Data Linked to You** for
   the eight declared types, with **App Functionality** only, and should
   have no **Data Used to Track You** section.
8. Have the release owner compare the preview with this file,
   `Plated/PrivacyInfo.xcprivacy`, and `docs/privacy-policy.md`.
9. Click **Publish** only after the production privacy URL, directory deletion,
   and Sign in with Apple revocation gates are complete. Apple requires the
   publisher to attest that the answers are accurate and will be kept current.
10. Record the publisher, date and a screenshot of the Product Page Preview in
    the release evidence without including customer data.

## Compliance conditions and risk areas

| Risk | Severity | Required mitigation |
|---|---|---|
| The deployed `/register` source is missing from this repository | High | Restore and audit the exact production source before publishing the label or changing the Sign in with Apple protocol. |
| Automatic Sign in with Apple token revocation is not implemented | High | Complete and live-test the server exchange/encrypted refresh-token/revocation flow in `docs/sign-in-with-apple-deletion.md`. |
| Public privacy page | Complete | October 18 policy verified live at `plated.food/privacy`; keep it aligned with future changes. |
| Notification server now processes selected shared activity | High | Publish the updated policy and eight-type App Store disclosure before public release. Real device authentication and delivery still require verification. |
| A future report service may store message text, media or reporter details | Medium | Re-evaluate Customer Support and Other User Content; update the policy, manifest and App Store answers first. |
| Instacart is later enabled | Medium | Audit the production partner's retention and privacy terms, disclose any transmitted grocery content, and update policy/label before flipping the feature flag. |

## Release approval record

| Approval | Owner | Status |
|---|---|---|
| Code/data-flow review | Engineering | Complete for current source; production `/register` remains unverified |
| Privacy/legal review | Release owner / qualified reviewer | Pending |
| App Store Connect entry and Product Page Preview | Account Holder, Admin or App Manager | Pending; UI authentication required |
| Published production privacy URL verification | Engineering | October 18 policy verified live from commit e6371a4 |

Any change to server fields, integrated partners, analytics, reporting payloads,
CloudKit access, or enabled feature flags requires this disclosure map to be
reviewed again before the changed build is submitted.
