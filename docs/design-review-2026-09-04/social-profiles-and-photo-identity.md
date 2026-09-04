# Social profiles and photo identity

September 4, 2026. This updates the interactive design preview. Native source is unchanged in this pass; contact import and account persistence remain implementation work.

## Restore the profile that was already conceived

`Plated/Views/PersonProfileView.swift` already establishes a cover image, overlapping avatar, name, bio, counts, and a three-column dish grid. A tile opens `PostThreadView` with a matched transition. The previous design preview reduced this to an author heading and a feed; that lost the personal destination the native work was aiming for.

The revised preview restores that structure. Tap a post author, reply author, or person in **Your Table** to open their profile. The global avatar opens your own social profile, with a settings control on that page. Settings retains an explicit route back to your social profile. These routes stay within the current navigation stack so returning preserves the underlying task.

- **Identity:** cover, avatar, display name, short bio. A monogram is the deliberate fallback until a photo is chosen. No fabricated portrait is assigned to a real person.
- **Relationship:** Your household or At your Table is a small, non-interactive line beneath the name. The user rejected the oversized outlined pill because it made relationship metadata look like an action. Keep the relationship visually subordinate to identity; reserve action styling for something the person can do. Household includes coordination of dinners and groceries. A Table connection includes the dishes and conversations shared with that audience.
- **Dishes:** a three-column photograph grid. Recipe and household badges identify the content before opening it. Each tile opens the corresponding full post and conversation, with its shared recipe copy available there.
- **Conversations:** questions and polls have their own section so they remain discoverable without pretending a text discussion is a dish photo.
- **Saved:** available only on your own profile and explicitly private. It shows the posts whose recipes you saved. Other people’s private cookbooks and saves do not become profile content.
- **Counts:** dishes, happy plates, and shared recipes derive from the same visible posts as the grid. Avoid follower counts or popularity labels that the product cannot substantiate.
- **Editing:** name, bio, portrait, and cover belong to a draft until Save. Cancel asks about discarding a changed draft. Changing a name preserves ownership and post associations through the person ID. A photo has a circular framing step with zoom and position; the same framing follows the avatar into the rest of the interface.

The three-column layout remains compact at 320 pixels. Empty dish, conversation, and saved sections explain what belongs there and offer an action where the viewer owns the profile. Profile tabs retain their selection when a person returns from a post.

## Apple ID and the person’s own contact photo

**The app cannot automatically obtain the Apple ID profile picture.** Sign in with Apple does not supply it. Apple’s framework engineer explicitly directs apps to ask for additional profile information through their own UI after authentication: [Apple Developer Forums, profile photos after Sign in with Apple](https://developer.apple.com/forums/thread/121998). Plated’s existing `ProfilePhoto.swift` already documents this limitation, and `SignInView.swift` requests the full-name scope rather than a photo.

The iOS SDK’s `CNContactStore.h` marks `unifiedMeContactWithKeysToFetch` unavailable on iOS (`NS_AVAILABLE(10_11, NA)`). Do not promise automatic My Card discovery, infer the owner by a matching name, or silently search the address book.

The supported design is an explicit **Use my contact photo** action:

1. After Apple authentication, prefill the name only when Apple provides it or Plated already has it. Returning sign-ins may not provide the name again; retain a valid previously saved name.
2. Open `CNContactPickerViewController` and ask the person to select their own card. This picker provides the selected contact without requiring blanket address-book authorization. [Apple contact-picker documentation](https://developer.apple.com/documentation/contactsui/cncontactpickerviewcontroller).
3. Read only available image properties from the selected snapshot. Check key availability before using `imageData` or `thumbnailImageData`. A nil image, unavailable key, undecodable image, or cancelled selection leads back to the photo choices without changing the draft.
4. Show the candidate in the circular framing step. **Use this photo** confirms the image for their Plated profile. Copy the image into Plated’s owned profile data; do not silently keep syncing later contact changes into a social profile.
5. Offer **Choose a photo** and **Take a photo** at the same step. A missing contact photo should say “This card doesn’t have a photo” and offer those alternatives. Continue without a photo remains available.

Only the confirmed photo is needed from Contacts. Do not copy phone numbers, addresses, birthdays, contact notes, or contact identifiers into the social profile. Photos-library and camera choices should use their appropriate native interfaces. On iPhone, a camera denial should lead to a library choice and a route to Settings if the person wants to enable the camera.

The browser preview models the choice and framing steps. It explicitly states that it cannot open iPhone Contacts. Its photo inputs can accept a local image; it does not authenticate with Apple or read the user’s address book. The separate profile-setup entry point makes this part of the design directly reviewable.

## Native implementation details that affect the experience

The native app already has `ProfilePhoto.square`, a 400-pixel square photo representation, and a parked-photo handoff from onboarding to the owner’s household row. Reuse the existing compression and handoff conventions while extending them for the person’s chosen framing. Do not create a second owner row during onboarding. Clear a parked draft when it is committed or deliberately discarded, including account changes.

A profile needs its own stable identity and versioned display fields. Display name, bio, avatar, and personal cover should resolve from that identity across post headers, reply authors, people lists, household seats, and profile screens. Keep authentication identifiers private and use the product’s stable person identity for social references. Existing name-based post filtering in `PersonProfileView` and author fallback matching in `PersonRef.author` must not remain the authority for ownership or profile lookup.

The current native bio lives in local `AppStorage`, and the editable cover is read from `HouseholdProfile` for the owner. Those are insufficient for showing a different person’s bio and cover on another device. Add appropriately shared person-profile fields, with owner-authorized edits and predictable version conflict handling. Keep the household cover separate from a person’s cover.

Resolve post visibility before generating profile counts, thumbnails, recipe badges, and conversations. A profile must not expose a household-only post to a Table-only connection through a thumbnail, counter, or direct link. The backing share/authorization model must enforce that visibility; a segmented UI is not an access boundary. Saved recipe ownership remains private even if the originating post later becomes unavailable. Do not infer a friendship from an address-book match.

A saved profile edit should update all avatar/name surfaces together. Failed saves preserve the draft and explain what can be retried. Cancelled image loads must not overwrite a newer draft. Native rendering should use a prepared thumbnail rather than repeatedly decoding a full-resolution photo, honor Dynamic Type and Reduce Motion, and retain accessible names for grid tiles and photo controls.

## Verification in this pass

Browser checks exercised a profile tile opening its correct thread; Sam’s household question appearing in Conversations; own-profile name/bio save; settings and return; dirty edit cancellation; private Saved empty state and a saved recipe appearing there; signup name validation; continuing without a photo; and the contact-picker explanation. The signup screen and own-profile tabs fit a 320-pixel frame without horizontal overflow. A local image fixture verified zoom and position controls and confirmed the same framing on the saved avatar. This does not verify native Contacts permission behavior, camera capture, Apple authentication, CloudKit authorization, or persistence across reloads.
