# Build 50 design correction — October 23, 2026

App source: `12ca9439ddf9cff2b9ca06795d2b5cf19a84fb8c`. Version **1.0.1 (50)**.

[Native / original side-by-side comparison](Comparison.html) · [Signed package](signed-package.json)

The original October 18 approval is unchanged. All 15 screen families and 36
states are mapped: 70 in-app appearance/state entries have native captures. The
remaining two entries are the lock-screen notification concept, not simulator
proof of delivery. iPad follows the later landscape-only instruction.

## Corrections

- Removed the ordinary-phone compact override that reduced Plan card padding,
  context spacing and meal photography. Cards use 18 points, sections 24 points;
  meal photos keep their 2:1 composition. Weather uses the approved spacing.
- Restored the cook picker title, explanatory copy, roster, Unassigned, explicit
  Save cook and Cancel. Sheet height follows roster size; accessibility text uses
  the large presentation. Save/cancel persistence was retested after this change.
- Returned photo replacement/removal to the image, with real 44-point targets.
  At accessibility sizes they move below the image to preserve readable controls.
- Corrected disabled primary actions to muted orange, section headings to 22pt,
  and comment placeholders to leading alignment. Reply remains a clear action.

## Verification and provenance

Result bundles are retained in `/Users/natemeadows/Plated/build`.

| Bundle | Observed result | Scope |
| --- | --- | --- |
| Release50-Logic | 720 passed, 4 Calendar opt-in skips | App regression baseline; before final presentation-only corrections. |
| Release50-Design | 40 passed, 1 iPad-only skip | Original state matrix and meaningful Save/Cancel, draft, reply and cooking paths. Intermediate correction binary still numbered 49; captures explicitly label this. |
| Release50-Compact | 17 passed | iPhone 16e, iOS 26.2, numbered 50; additional states, invitation receipts, publication, Plan and replies. |
| Release50-IPad | 5 passed | iPadOS 27, both appearances/default and AX5; landscape and draft-preserving rotation attempt. |
| Release50-Current | 7 passed | iPhone 18 Pro/iOS 27; refreshed native matrix, AX5, Plan/context, replies and picker. |
| Release50-Photo | 4 passed | Final photo controls in both appearances, geometry, removal, rotation, AX5 and comment input. |
| Release50-Picker | 2 passed | Exact final source, dark cancellation and light save/persistence after roster-sizing correction. |

No failed tests in these runs. Captures from before later changes are retained as
intermediate evidence, not relabeled final. Later targeted captures supersede their
affected paths; no claim that every screenshot came from the signed IPA.

Visual review covered all 70 mapped entries in both appearances, plus enlarged
side-by-side comparisons of every screen family. It checked hierarchy, type,
spacing, controls, media, empty/pending/saved/checked states, keyboard and safe
areas. The comparison keeps actual fixture data; different names/counts/photos
are not production sample data. Activity excerpt and thumbnail paths were also
source-reviewed; the generic activity fixture has no linked comments/photos and
therefore cannot visually prove those richer rows.

The browser honors iPad screenshot orientation metadata for landscape presentation;
the stored native image bytes are unchanged. Original portrait approval remains
visible as historical reference, not the current orientation requirement.

## Disclosed adaptations and remaining limits

Global + remains because the original Create and iPad annotations require it.
System sheets, keyboards and safe areas follow iOS. Target areas are at least44pt
rather than copying undersized prototype glyphs. Real forecasts use official
attribution; isolated fixture forecasts say Preview weather. Sample avatars and
membership activity never establish cross-account synchronization. Cream secondary
text retains the previously documented accessibility contrast correction.

Fresh physical VoiceOver, phone notification registration/delivery, two-account
sync, widgets/Live Activities, Calendar permissions, iOS18 and an in-place upgrade
from the prior TestFlight build are unavailable/unverified. The user explicitly
instructed continuation without the phone and release without live checks. That
exception is not verification. No new notification backend deployment occurred in
this design release; the previously observed lack of active verified installations
is not resolved by these screenshots.

[Full route inventory with historical checks kept separate](screen-state-inventory.md).
This is a scoped beta correction and its evidence, not zero-defect or App Store
certification. Unexercised routes remain open rather than silently counted as passes.
