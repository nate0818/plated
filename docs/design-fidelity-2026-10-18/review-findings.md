# Independent implementation review — October 18, 2026

Reviewed the uncommitted design-fidelity candidate in the isolated worktree based on `fc87ad1`, against the unchanged original October 18 approval. The initial review used source plus native accessibility trees. Later sections identify narrowly scoped pass2 visual findings and pass3 iPad display review; none is a full visual, interaction, device, or release pass.

## Confirmed findings and bounded corrections

| Finding | Evidence | Correction / remaining proof |
| --- | --- | --- |
| Cream secondary text was below 4.5:1 on filled surfaces. | Original approved `#67715E` is 4.386:1 on `#EEEEE4` and 4.092:1 on `#E2E8D9`; it is 4.858:1 on canvas. Cooking timer status and completion context are normal-size text on fill. These ratios use WCAG relative luminance, not screenshot estimation. | Root applied `#606A57` in cream only, with the matching widget token. This is an explicit accessibility correction to palette usage; the original artifact remains unchanged. Fresh native contrast diagnostics still required. |
| Profile Posts and Saved tabs were narrower than 44 points. | Initial `polish-profile-light-tree.txt`: Posts 31.7×44, Saved 33.7×44. `PersonProfileView` set minimum height only. | Root added label-level minimum width 44. Verify final native geometry and navigation. |
| Table author targets were 36 points high although the containing row reserved 44. | Initial `polish-table-light-tree.txt`: author 150.3×36. In both post and question cards, `contentShape` preceded the minimum-height frame. | Reordered the label modifiers: min 44×44, then content shape. Kept 36-point avatar and containing-row geometry. Fresh tree/action proof required. |
| Table caption and comment-count targets could be too small. | Initial Table tree: one-line caption 362×19.3; two-line caption 362×40.7; comment count as narrow as 40.3×44. | Caption content reserves a 44-point minimum height; comment-count and caption “more” controls reserve both dimensions. Short captions now consume real space rather than overlapping adjacent action targets. Photo-only empty captions remain empty. Fresh native review required. |
| Thread post-author target was 38.3 points high. | Initial `polish-thread-light-tree.txt`: author 150.3×38.3. | Added min 44×44 inside its label, before its content shape; avatar stays 36. Fresh native proof required. |
| Household stats and Plan Household link enlarged the Button wrapper rather than its label. | Source: `HouseholdHomeView.page`, `PlanHouseholdView.body`; the same modifier placement was confirmed to yield undersized frames in the initial Plan/Profile captures. These specific two controls have source-only evidence. | Moved target sizing and content shape inside each label. Fresh native geometry/action proof required. |

Initial evidence directory: `/Users/natemeadows/Plated/build/fidelity-initial-named`.

## Follow-up correction requiring native proof

`MainShellView` previously reserved a fixed 60 points for the minimized cooking strip while its text used uncapped Dynamic Type. Root now measures `resumeStripHeight` separately and reserves that height plus 8 points. Exercise AX5 with an active minimized cooking session, particularly Groceries, before treating bottom-reservation behavior as verified.

## Checks performed

- Read the standing project instructions, release quality standard, design contract, and original review renderer/CSS.
- Reviewed shared palette, typography, icon/button and tab-bar changes plus affected social, Plan, recipe and cooking paths.
- Read the initial native accessibility trees; did not count completed capture tests as target or visual passes.
- After these bounded target edits, Swift frontend syntax parsing passed for TableFeedView, PostThreadView, HouseholdHomeView and PlanHouseholdView.
- `git diff --check` passed.
- No build, simulator mutation, physical-device check, account operation, publication, or original approval edit was performed by this review.

## Invitation-copy acceptance correction

The original annotation required a fresh invitation to explain restored access. Previously the verified fresh grant and initial invitation shared generic Join wording. The bounded correction adds `HouseholdReinvitation.VerifiedInvitation` presentation proof, created only when the fetched root contains an existing valid identity/seat grant. `HouseholdSync.preview` carries that proof without changing its state precedence or any join/backend authorization. `HouseholdInvitationCopy` uses it only in ready/switch states, with “Rejoin” and “invited you back” wording; removed, already-member, own-link and resume states remain singular even when an older proof is still present. The ready-state button uses Rejoin household. Loading and read-failure paths are unchanged.

Five new pure regression tests exercise actual grant/revoke/accept snapshots: fresh versus old links, fetched records versus stale local cache, both acceptance/removal orders, present-state precedence, and unchanged normal/unknown invitation copy. Swift frontend syntax parsing and `git diff --check` passed after the edits. Unit execution, fresh native copy/reflow/action review and live two-account removal/rejoin remain pending; no live behavior is claimed.

The composer annotation was also reconciled precisely: Change photo replaces an attachment, and Remove sits on the image. The mock calls the replacement control Edit photo. Its text does not require a crop editor, so that was an overinterpretation rather than a missing capability. The exact label difference remains disclosed in the ledger.

## Compact pass2 visual findings and subsequent source corrections

Evidence: `/Users/natemeadows/Plated/build/fidelity-compact-pass2-named`. These captures predate the final invitation, publication and reply patches. Representative Plan, Table, composer, thread, Profile, recipes/detail, Groceries and Create renders were inspected in both appearances, with available AX5 captures.

| Confirmed observation | Correction / remaining proof |
| --- | --- |
| Empty composer prompt visibly truncated to “What’s / worth sha…” at AX5 in `polish-composer-AX5.png`; the attachment-scroll capture retained the ellipsis. | Root replaced the native TextField prompt with a real multiline label and moved the privacy reminder into the scrollable body at accessibility sizes. The submitted action remains fixed. Source inspected; fresh AX5 empty/typed/keyboard render and focus behavior still require review. |
| Empty Directions was missing from Pancake Dinner detail in both appearances. Original approval explicitly renders the Directions anchor plus “No written steps added yet.”; native had only Ingredients and omitted the empty section. | Root now always supplies the Directions anchor and renders that exact empty-state sentence when no instructions/steps exist. Source inspected; native empty/populated section jump, selected state, scroll and footer clearance retests pending. Empty optional Notes remains omitted. |
| Cream Table + glyph was blank in `polish-table-light.png`, although its tree exposed `tray-create` at 207,32,44,44. It was visible in later same-pass `fidelity-navigation-targets-light.png` and in the dark Table capture. | This is an intermittent/capture-specific rendering discrepancy, not proof of a persistent cream token bug. Root added a settled creation-target capture/check. Fresh render still pending; no speculative production change was requested. |
| Native comparison lacked a positioning parent for absolute `.app`; explicit image display also overrode native `[hidden]` behavior. Capture index was empty. | Root added `.mock { position:relative }` and `[hidden] { display:none!important }`. Source fixes inspected. Exact-state native index population and browser review remain pending. The original proposal renderer/CSS is unchanged. |

## Pass3 iPad display review — limited scope

Source/build record: `candidate-source.json` describes the unreleased pass3 simulator candidate (source digest `fa424c6dc31154741e0fe1ff9dddcb0f7e8eed008f561ae6599ddb34ecfe156c`, executable SHA-256 `772d0104a18e9959c925cf568275bee33ca873618d477d2551bad79649d11065`). Evidence is the `polish-ipad-display-*` XCUIScreen attachments identified by `/Users/natemeadows/Plated/build/fidelity-ipad-pass3-attachments/manifest.json`, now also named under `/Users/natemeadows/Plated/build/fidelity-ipad-pass3-named`.

| Physical orientation requested | Display evidence inspected | Observation |
| --- | --- | --- |
| Landscape left (3) | `polish-ipad-display-3.png` / `D770AD3A-9C0E-4652-9F74-97067625F2FA.png` | Full landscape display; bounded date rail; dinner/main action left and weather/history/activity right. No clipping or overlap found in the shown default dark Plan. |
| Portrait (1) | `polish-ipad-display-1.png` / `D793CB19-9E59-480C-8F08-4E7EB83B99D0.png` | The complete landscape interface remains sideways, consistent with the later landscape-only instruction. No portrait reflow, blank crop or overlapping columns found. |
| Landscape right (4) | `polish-ipad-display-4.png` / `5456A3C1-955D-4500-91F3-7F7B9CE22A64.png` | Same full-width landscape composition; title, date, meal photo, cook, action and context remain visible and separated. |
| Portrait upside down (2) | `polish-ipad-display-2.png` / `53A17742-E031-4E98-872D-2364221BDC57.png` | The landscape composition remains rotated in the other physical direction, with all shown task/content regions intact. |

Paired landscape trees place the weather at x679 with width456 and meal summary/photo target at x93 with width543; the cooking action is 543×48 at y684, above the tab bar beginning y767. The portrait-attempt trees rotate those dimensions as expected. These observations support only default dark Plan in this iPadOS 27 simulator; they do not establish cream, accessibility-size, narrower-window, current-shipping-OS or physical-device fidelity. Tomorrow lies below the captured viewport and was not visually reviewed here.

`fidelity-ipad-pass3.log` reports `testIPadStaysLandscapeAndUsesTwoColumns` passed (1 test, 0 failures). That test asserts the caption equals “Keep this draft while rotating.” after portrait attempt and return to the other landscape orientation; it also asserts the text field remains hittable. Draft preservation is recorded as that UI assertion evidence only. Draft `app.screenshot()` images and `polish-ipad-orientation-*` images are not treated as visual proof because this XCTest path can misorient/crop them. No live sync, physical rotation/VoiceOver, scene resize, termination/relaunch or device keyboard claim follows from the test.
