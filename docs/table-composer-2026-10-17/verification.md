# Table composer verification — October 17, 2026

## Implemented behavior

- General posts accept writing alone, a photo alone, a title, or their combination. An ingredient or restaurant does not need a dish name. The primary action is **Post to Table**.
- The author's identity and chosen private Table appear before writing. Multiple writable Tables still require an explicit choice. Camera/library, title, tags, and poll controls are optional additions.
- A picked photo's loading/failure prevents silent publication without that attachment. Change, retry, and remove are explicit. Removed or superseded photo requests cannot overwrite a newer choice.
- Poll choices are trimmed, deduplicated, bounded to four, and include a typed pending choice. One choice or a missing question has a visible explanation. Poll-row identity survives deletion.
- Close offers Save draft, Discard post, and Keep writing. An atomic draft retains photo, writing, title, people, audience, and pending choice. Legacy Dish drafts remain readable. Preview draft files are isolated from real drafts.
- A local post is durable before dismissing; publication remains pending until the existing CloudKit path confirms it. Repeated publication is guarded. Preview tests never publish their fixtures.
- General posts render in the feed, thread, profile, and Table widget. Profile text tiles show their writing. Recipe-derived and existing dish posts retain cookbook actions; ingredient/place posts do not imply they are recipes. Activity copy says “shared” and “post.”
- No CloudKit field additions. The existing `kind` string carries `post`; old `dish` and `ask` rows remain supported.

## Evidence

- Xcode 27 / iOS 27 app and widget build: passed. Final build log: `/tmp/plated-composer-commit-build.log`.
- Full unit suite: 502 tests executed, four opt-in Calendar tests skipped, zero failures. `build/table-composer-unit.xcresult`.
- Focused content, notification, and widget regression suite: 60 tests passed, including the subsequently added general-post widget test. `build/table-composer-final-unit.xcresult` (iOS 26.5 compact phone).
- Standard phone functional suite: five scenarios passed after the draft confirmation was made an explicit native alert. `build/table-composer-ui-verified.xcresult`.
- Compact iPhone SE: text-only publication/thread, photo removal/failure, photo+people draft restore, pending-poll-choice restore, and AX5 input passed. An initial native photo-picker test failed because this simulator offers a camera/library menu; the test was corrected to use that menu. `build/table-composer-compact-ui.xcresult`, followed by the successful native-picker run in `build/table-composer-final-accessibility.xcresult`.
- Final complete composer suite: **8 passed, zero failures**, in `build/table-composer-complete-ui.xcresult`. This includes Done clearing focus for caption, title, and poll input; large-text adaptation; optional photo removal; photo+people draft recovery; photo failure; camera/library choice and native picker cancellation; pending poll choices; and text-only publication through feed to thread. The final local activity sentence was polished afterward and the app/widgets rebuilt successfully; no interaction behavior changed.
- Design/token checks and all 159 deployed CloudKit fields: passed. No schema migration or deployment required.
- Screenshots reviewed: compact and standard iPhone, iPad, light/dark, empty/photo/error, text-only feed/thread, AX5/long title. The native photo-picker open/cancel path was tested; transition-time captures were excluded. The iPad photo screenshot was captured with Increase Contrast enabled; the setting was restored afterward.

## Accessibility and limits

The compact-phone audit returned no contrast, hit-region, description, or clipped-text issues. iOS 27's audit reports `Contrast failed for SwiftUI.AccessibilityNode` without attributing an element. This remains an unresolved automated finding; it is not counted as a clean accessibility pass. `accessibility-phone.txt` and `accessibility-compact.txt` retain the results. Direct calculation of the composer's semantic text-color pairs gives 4.96:1 or greater in both appearances; see `contrast.txt`. This calculation does not dismiss the runtime warning.

The initial AX5 header occupied two large lines; it now uses an appropriately smaller semantic heading style at accessibility sizes and remains one line in the tested phone layout. Optional controls reflow to one column. The primary action remains reachable. Focus uses one explicit owner for all three fields; a competing helper focus binding was removed.

Static audit findings in `static-audit.txt` include the wider existing app. Composer findings were reviewed: full-screen camera owns its safe areas; icon/avatar dimensions have 44-point control targets; bounded photo preview uses aspect fit. Index-based poll identity was corrected. Existing motion tokens honor Reduce Motion, and the composer introduces no custom material or motion; live reduced-effects and physical VoiceOver interaction were not certified in this pass. Screenshots with a simulator input accessory do not establish a complete physical software-keyboard check.

No physical phone, camera capture, two-account CloudKit delivery, multi-photo/video posting, or place-search feature parity is claimed. Posting still supports one photo. The outstanding server-side social push delivery gap in `docs/social-delivery-2026-10-17.md` remains a release blocker. These changes have not been distributed to TestFlight; build 40 remains the distributed beta.

## Design review score

Provisional **82/100**, standard profile: platform 13/15; layout 13/15; native semantics 13/15; interaction 17/20; motion/material 12/15; accessibility 6/10; implementation 8/10. Unverified assistive/reduced-effects behavior caps the score at 84. The unresolved audit finding and physical-device gates prevent a release-readiness or Instagram-parity claim. This score assesses the changed posting surface, not the entire application.
