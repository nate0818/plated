# Plan follows the selected day · 17 October 2026

The user requested one day's content below the date row. Plan now opens on today, changes the visible day when the date row changes, and does not render Coming up, future weeks or earlier-day lists. Other local/shared meals belonging to the selected date remain available below its dinner. Calendar and Back to tonight remain available.

Only the date navigation pins during vertical scrolling. The greeting can scroll away, preserving room at accessibility text sizes. Changing the date returns to the top of that day's content. Existing move/drop and date-wheel navigation are retained.

Restoring the date row exposed a VoiceOver defect: focus could scroll to another date and accidentally change the day. VoiceOver now reads one adjustable selected date with day/week/Today actions, then continues to dinner. Touch users retain the visible date row. The regression asserts actual spoken output and unchanged selection; XCTest still enumerates hidden date controls, so its raw element count is not treated as VoiceOver reading order.

## Evidence

- `selected-day-device.xcresult`: **2 passed**, on the connected iPhone 18 Pro/iOS 27.2. Date changes, repeated selection, vertical scrolling, empty past day, Back to tonight and Calendar return passed. Actual VoiceOver read the selected date, named dinner and Start cooking without changing the date. `voiceover-selected-day-device.txt` retains that app-specific speech.
- `selected-day-verified.xcresult`: **4 passed**, on iPhone 17 Pro/iOS 27 Simulator. Actual VoiceOver, ordinary date selection, largest accessibility text, and selected-day shared/local replacement passed.
- `selected-day-compact.xcresult`: **3 passed**, on iPhone SE/iOS 26.5 Simulator. Covers ordinary selection, largest accessibility text with multiple same-day meals, and a shared dinner that disappears when another day is selected.
- `selected-day-viewport.xcresult`: **2 passed**, on iPhone SE/iOS 26.5, using the final build. Date navigation and largest accessibility text passed after the clipping/copy polish. Screenshots confirm scrolled meal content no longer paints behind the status bar; the pinned date row remains available and same-day breakfast remains reachable.
- `selected-day-wheel-native.xcresult`: **6 passed**, covering existing interruption, cancellation, settling, feedback and geometry contracts.
- Both Simulator and signed-device builds passed. `make design` checked 163 Swift files. Static SwiftUI scans reported no high-severity findings; existing generic geometry, frame and animation flags were reviewed in context.

The phone checks used the in-memory review fixture. The temporary UI runner was removed and the review process terminated. No Home Screen widgets were changed. The viewport clipping and supporting meal-copy polish followed the physical interaction check; they are covered by the final Simulator captures. The final signed build was installed successfully on the connected iPhone after those checks. Both dedicated audit Simulators were then shut down.

This record supersedes the earlier Tonight/Coming up layout screenshots. It does not clear the separate live two-account or remaining release gates in [README.md](README.md).

## Reviewed captures

- [Selected day](verified-screens/selected-day-today.png) and [another date](verified-screens/selected-day-tomorrow.png).
- [Shared dinner](verified-screens/selected-day-shared.png) and [empty past date](verified-screens/selected-day-empty-past.png).
- Final compact-device build: [same-day breakfast at largest text](verified-screens/compact-selected-day-largest-text-breakfast.png) and [switching dates at largest text](verified-screens/compact-selected-day-largest-text-next-day.png).
