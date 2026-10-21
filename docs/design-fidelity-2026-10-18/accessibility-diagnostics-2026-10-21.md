# Compact iPhone accessibility diagnostics — October 21, 2026

Environment: isolated iPhone 16e / iOS 26.2 simulator, Editorial and cream
fixtures, current design candidate. These `performAccessibilityAudit` probes
collect findings and return `true`; a green XCTest status does not mean no
accessibility issues. Raw text and result bundles are under
`/Users/natemeadows/Plated/build/Compact-Accessibility-Diagnostics-20261021.xcresult`
and `/Users/natemeadows/Plated/build/Compact-Accessibility-After-20261021.xcresult`.

| Finding | Before | After correction | Assessment |
| --- | --- | --- | --- |
| Table thread post photo has no description | 1 | 0 | Real issue. The post photo now supplies an author/post-context accessibility label. This does not invent a visual description the user never provided. |
| Table comment link label is only `cooking.nytimes.com` | 1 | 0 | Real issue. The accessible action now says whose web link opens; the displayed domain remains available as a hint. |
| Contrast, named Plan nodes | 2 | 2 | Xcode flags `Salmon Night` and `Serves 4`. The inspected cream Plan render has dark text on a solid cream card. Defined `ink`/`fill` contrast is 10.68:1; `inkSecondary`/`fill` is 4.87:1. The detector appears to misattribute the SwiftUI node background. This is a token calculation and visual review, not a measured pixel-level pass at every glyph edge. |
| Contrast, named Grocery node | 1 | 1 | `Sun · Steak Bowls` uses the secondary token on a cream surface. The token pair is at least 4.87:1 on `fill` or 5.39:1 on `canvas`; its actual ancestor/background and rendered pixels should be confirmed before dismissing the warning. |
| Contrast, named Thread nodes | 3 | 3 | The time/Reply secondary token on dark canvas is 8.92:1; the domain chip accent on dark chip fill is 7.48:1. The inspected Editorial thread screenshot shows readable text. Audit still flags the nodes, so retain raw findings. |
| Contrast, unattributed comment node | 1 | 1 | No element is attached in the diagnostic. Cannot conclusively classify it from the report alone; manual screenshot review showed no obvious unreadable text. Physical VoiceOver and additional contrast inspection remain open. |

Contrast calculations use the sRGB luminance formula on the values in
`Plated/Support/Theme.swift`. They do not substitute for live VoiceOver gestures,
system Increase Contrast, variable image backdrops or all Dynamic Type sizes.
