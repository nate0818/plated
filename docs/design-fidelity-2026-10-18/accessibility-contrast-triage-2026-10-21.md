# Compact contrast-probe triage — build 46 candidate

This records manual review of the **seven collect-only contrast findings** in
`Compact-Accessibility-After-20261021.xcresult`. The probe deliberately
continues after reporting an issue, so a passing test invocation is not an
accessibility pass. The candidate app source is `7b4d56d` (1.0.1/46); this
review does not cover every screen or physical VoiceOver.

| Probe target | Actual style/background in source | Token contrast | Interpretation |
| --- | --- | ---: | --- |
| Thread comment “1 hr. ago” and “Reply” | `Color.inkSecondary` on `Color.canvas` in `PostThreadView.threadComment` | 8.925:1 dark; 5.389:1 light | Both exceed 4.5:1. The recorded frames at y 638/624–668 sit outside the thread scroll viewport ending at y 602.5, under its fixed composer. They are scroll content, not simultaneously visible text at that sampled offset. |
| Thread web-link domain | `Color.accentText` on `Color.chipFill` in the comment link chip | 7.344:1 dark; 6.316:1 light | Both exceed 4.5:1. The link has its own descriptive accessible label and a 44-point enclosing target. |
| Grocery origin “Sun · Steak Bowls” | `Color.inkSecondary` on the grocery `Color.canvas` row | 8.925:1 dark; 5.389:1 light | Both exceed 4.5:1. Its recorded y 601–615 frame is below the scroll view ending at y 555, which explains a sampled-pixel failure at that offset. |
| Plan “Serves 4” | `Color.inkSecondary` on the neutral dinner `Color.fill` | 7.710:1 dark; 4.865:1 light | Both exceed 4.5:1. The actual action has a 44-point target, “Change servings” label and current serving value. |
| Plan “Salmon Night” | `Color.ink` on the neutral dinner `Color.fill`, above the recipe artwork | 12.944:1 dark; 10.677:1 light | Both exceed 4.5:1. The contrast probe attached to the title’s child text inside a combined dinner button; the title is not laid over the image. |
| Comment probe with no attributed element | No element/frame was emitted | Not measurable | Cannot classify as a product contrast defect or a pass. Preserve the raw probe and inspect this screen in the fresh rendered inventory. |

Ratios are WCAG relative-luminance calculations from the native tokens in
`Plated/Support/Theme.swift`, not sampled screenshots. The dark comment-thread
render from `Compact-Accessibility-After-20261021.xcresult` was visually
inspected and its comment metadata, controls and link styling are readable.
These findings narrow the named token/occlusion questions; they do not close
the full visual/accessibility ledger, minimum-iOS coverage, or device gestures.
