# Collaboration and presentation refinement — October 16, 2026

Addresses the three browser comments after the product-story revision.

The hero now leads with what is for dinner, who is cooking, and what to buy.
The walkthrough introduces sharing the cooking, then names the Plan step
“What’s for dinner. Who’s cooking.” A semantic table makes the collaboration
concrete: Tonight / Salmon Night / You; Tomorrow / Pizza Night / Sam;
Tuesday / Steak Bowls / Riley. It is visibly labelled Example household.
These assignments match `Plated/Support/SampleData.swift`, offsets 0, 1 and 4,
and the existing native captures. No app interface or activity was invented.

Step numbers use the existing cream `--ink` role. Measured against canvas
`#191C17`, cream `#EDF0E6` has 14.93:1 contrast and secondary `#B0B8A8` has
8.42:1. The prior coral was 5.56:1, above the WCAG AA normal-text minimum;
cream gives the small numbers more contrast. This is a targeted contrast check,
not a claim of full-site ADA compliance. Reference:
https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html

The Table figure no longer has a contrasting fill or card radius. Its phone,
caption and surrounding space sit directly on the main canvas.

Validation: production build, TypeScript and targeted ESLint passed. Browser
checks and captures cover the Plan example, neutral step labels and unframed
Table presentation. The existing sticky walkthrough and mobile inline screens
remain in use. No deployment was requested.
