# Additional release checks with the phone disconnected · 17 October 2026

The user authorized continuing checks that do not require the phone. All runtime work in this pass uses the two dedicated audit Simulators. No phone connection, Home Screen/widget changes, real iCloud-account changes, release upload or publication is part of this pass.

## Repairs

- Calendar removal retained `calendarEventID` when an event had already been deleted in Apple Calendar. The new EventKit test reproduced this before the repair. Removal now clears a stale link after confirming Calendar access; denial throws and preserves the link for retry.
- The gathering form had no explicit keyboard-dismissal control. With the keyboard open, forward VoiceOver traversal skipped the lower Calendar toggle and continued into keyboard keys. The form now provides Done while editing, Next/Done keyboard labels, and owned field focus. The corrected VoiceOver journey now passes through text entry, keyboard dismissal, guest changes, the Calendar toggle and a local save.
- Several recipe fields did not use the editor’s existing focus state, so its Done keyboard bar was missing while editing those fields. Title, description, notes, new-step, metadata and nutrition fields now use the shared editing state.
- Profile save errors were visible but intermittently absent from the observed VoiceOver traversal. Failed Save now explicitly announces the error on every attempt, including retries with the same message, and exposes it as the Save button’s accessibility value. Focus-only experiments were inconsistent and were replaced by the explicit announcement already used in the recipe/gathering forms.

## Completed checks

- `extra-calendar-fixed.xcresult`: **3 passed**. Real EventKit create/update/recreate/remove; move a saved event to a second temporary calendar, then change its date/time without duplication or changing its calendar; remove an externally deleted event and clear its local reference. Only UUID-marked test events/calendars are created and removed.
- `extra-calendar-denied.xcresult`: **1 passed**. Denied access produces an error and preserves the reference for retry. The simulator's permission state is set explicitly; real permission-prompt coverage remains in the earlier release record.
- `extra-widget-date-boundaries.xcresult`: **6 passed**. Production provider/snapshot code handles 23-hour and 25-hour DST days, a Los Angeles → New York date-boundary change, midnight expiry, missing/stale data, and opaque deep-link IDs. These are in-memory calculations, not an observed WidgetKit overnight run.
- `native-after-extra-checks.xcresult`: **422 executed, 418 passed, 4 intentionally skipped, 0 failed**. The four opt-in Calendar checks were run separately above. This suite ran before the final recipe keyboard/profile announcement changes; those receive targeted UI coverage. Includes household/Table queues, conflict/merge behavior, removal/revocation and authorization contracts; this does not establish live two-account delivery.
- `gathering-draft-after-keyboard-fix.xcresult`: **1 passed** on iPhone SE. Failed-save gathering drafts remain recoverable after relaunch.
- `recipe-keyboard-fields-retest.xcresult`: **1 passed** on iPhone SE. Title, notes and a decimal nutrition field retain entered text and expose a working Done control; dismissal and discarding edits passed.
- Gathering and recipe form tests in `extra-voiceover-forms-final.xcresult`: **2 passed** through the actual iOS 27 VoiceOver service. Gathering covers text input, Done, guest increment, Calendar toggle and local save; recipe covers failed Save, retained edits, Keep writing and Discard restoring the original recipe. This mixed bundle also has a failed profile diagnostic and is **not** an overall passing bundle. XCTest synthesizes form input; these tests do not establish physical gestures.
- `voiceover-profile-announcement.xcresult`: **1 passed**. Profile bio entry, Done, first failed Save, repeated failed Save, spoken error on both attempts, retained draft and Cancel dismissal passed through the actual iOS 27 VoiceOver service. See [spoken transcript](voiceover-profile-form-transcript.txt).
- Native accessibility actions in Device Hub: Plan’s Next week and Today changed the selected date and content; Grocery Remove reduced the count and Undo remove restored the row/count. Purchase marked the row Purchased and reduced the count. Purchase undo was interrupted by test teardown and is not counted as verified.
- Final **Release configuration build passed**, app and widget extension **1.0.1 (33)**, minimum iOS 18. Deep/strict code-signature verification passed. This uses development signing; it is not an App Store archive or uploaded release. [Build metadata and executable hashes](BUILD_VERIFICATION.json).
- `make design`: 163 Swift files passed; shared native/widget tokens, website tokens and Live Activity model parity passed; `git diff --check` passed.

## Diagnostic attempts

`extra-calendar-probe.xcresult` had Calendar permission denied by the earlier denial-flow fixture. Restoring access exposed the real stale-reference failure in `extra-calendar-granted.xcresult`, repaired and retested above. Initial VoiceOver input used single taps, which selected text fields without activating them. The corrected harness uses simulated double taps. These attempts are not release passes.

`voiceover-profile-final.xcresult` and the earlier profile focus probes reproduced inconsistent error speech. They are diagnostics, not passes; the final implementation uses an explicit announcement and a persistent accessible Save value.

The host keyboard rotor probe did not change the selected date and failed; the temporary probe was removed. Rotor gestures remain on the physical-device checklist. Early form runs also exposed harness input/query errors. Only the explicitly passing tests above count as evidence.

Automatic approval review initially mistook the in-memory widget timeline tests for Home Screen edits. Their complete source was inspected to establish that they contain no SpringBoard, widget installation/removal or Home Screen operations; the isolated calculation-only run was then approved and passed.

The [gathering save-ready](verified-screens/voiceover-gathering-ready-to-save.png), [recipe save-failure](verified-screens/voiceover-recipe-save-failure.png), [compact recipe decimal-keyboard](verified-screens/recipe-decimal-keyboard-done.png) and [profile error with retained draft](verified-screens/voiceover-profile-error-retains-draft.png) screenshots were visually reviewed. Error text and controls remain readable; entered values are preserved.

These latest repairs have **not been installed on the phone**, which the user disconnected. No personal widgets or Home Screen arrangement were changed during this pass. The temporary UI test runners were removed and both dedicated audit Simulators were shut down after the tests; other simulators were left alone.

The release remains uncleared pending the outstanding real-device and two-account checks in [README.md](README.md).
