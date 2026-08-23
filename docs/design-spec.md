# Plated — Design Specification v2.0 · "Quiet chrome, earned color"

The single source of truth for Plated's visual and interaction design. Every value below is a decision, not a suggestion. iOS 18+, SwiftUI, bundled OFL fonts (Gabarito + Plus Jakarta Sans), no third-party UI libraries.

v1.0 (cream/serif "plates on porcelain") is retired; see git history. This register was locked 2026-08-21 against the design canvas ("Plated Journey" artifact) after an A/B pass.

**The idea in one sentence:** the chrome is a white tablecloth — near-monochrome, calm, invisible — so every family's own food photos carry all the color; accent color is *earned*, appearing only when something good happens.

---

## 1. The law

- **Quiet chrome.** White canvas, ink text, faint labels, hairline borders. No ambient accent color, no tinted headers, no decorative gradients in the main app (onboarding may use barely-there radial tints of the food colors).
- **Earned color.** Tomato `#FF5A3C` appears ONLY as: the + button (the single always-tomato element), a plate reaction landing, "Set a place"-class primary committing CTAs, and today's marker in the cook grid. Mango `#FFB020` exists only in the brand mark and the chef's kiss. If tomato is on screen twice at rest, something is wrong.
- **Fun lives in motion, haptics, and voice** — bouncing tab icons, the spinning +, "set a place", "nothing plated yet" — never in loud paint.
- **Two-shape grammar.** Circles are dishes and people (photos, avatars, reactions, the ring). Rounded rectangles are moments and containers (feed cards, day rows, sheets).
- **Photos are user-submitted.** Every food image belongs to somebody at the table. No stock catalog imagery in product; bundled sample photos are seed/stand-in content only.

## 2. Color tokens (Theme.swift)

| Token | Hex | Use |
|---|---|---|
| canvas | `#FFFFFF` | every background |
| ink | `#221B14` | primary text, active icons |
| inkSecondary | `#8A8074` | supporting text |
| inkFaint | `#B5AC9E` | micro-labels, inactive icons |
| hairline | `#F0EBE4` | card borders |
| hairlineSoft | `#F7F3EE` | row separators |
| hairlineDashed | `#EFE7DD` | empty-state dashes |
| navHairline | `#EFECE7` | floating bar edge |
| fill / chipFill | `#F4F1EC` / `#F7F5F1` | neutral avatar, link chips |
| tomato / tomatoPressed | `#FF5A3C` / `#D6401F` | earned color only |
| mango | `#FFB020` | chef's kiss, brand mark |
| basil | `#3DA35D` | progress ring, "Seated", toggles |
| amber / grape | `#C88A00` / `#B95CF4` | person palette |
| tints | `#FFEDE3 #EDF5EF #FFF4DC #F5EDFB` | person avatar washes |

People get fixed (tint, tone) pairs via `PersonTone`; the rotation is tomato → basil → amber → grape.

**After Dark** — every token above carries a dark twin (`Color(light:dark:)`), switched by the After Dark toggle in Home via `preferredColorScheme`; the app never follows the system appearance. The dark room is warm espresso, never cool gray: canvas `#16120E`, ink `#F4EDE3`, secondary `#A79B8B`, faint `#6B6157`, hairlines `#2B241C`–`#342C22`. Accents lift a touch so they still land (tomato `#FF6448`, basil `#55BE76`, mango `#FFB63A`, amber `#E3A83C`); tints deepen to embers (`#39241C #1F2E24 #332A15 #2E2138`). Shadows go true black. Decorative glows sleep in the dark — chrome recedes further, photos glow harder.

## 3. Type

- **Gabarito** (display). **Semibold (600) is the working weight at display sizes** — screen titles 25–27/600, section and page titles 20–24/600, card titles 22/600. Sheet titles 19/700. Negative tracking on large sizes (−0.3 to −1).
- **ExtraBold (800) survives in three places, all of them small or ceremonial**: the onboarding heroes and sign-in wordmark (32/800, 22/800), the launch wordmark, and small Gabarito *numerals* — the month grid's day numbers (13/800) and the recipe composer's step numbers (14/800), where the weight is doing the work a larger size would otherwise do. It is not used at display sizes in the running app.
- **Plus Jakarta Sans** (everything else): body 14–15, chips/buttons 13/700, micro-labels 12/700 with +1.0 tracking, uppercase.
- **Type floors — what the code actually does.** `MicroLabel` (12/700, +1.0 tracking) is the standard tracked label and the one to reach for. Hand-rolled emphatic captions run 10–11 in bold or extraBold — the weekday caps in the week and month grids, the tab labels, the HOST caption. **9pt is the absolute floor**, and it is reached exactly once: the numeral inside the activity badge, where the containing shape carries the meaning. Nothing renders below 9.
- Registered at launch via `CTFontManagerRegisterFontsForURL` from `Resources/Fonts`; use `Font.gabarito(_:_:)` / `Font.jakarta(_:_:)` only.

> **Weight law changed 2026-08-22**, on Nate's call — "reduce the font weights of the headlines, they're too heavy" — and confirmed by him as final on 2026-08-23. v2.0 specified 700–800 across display type; that read as shouting once the chrome quietened. Roughly thirty call sites came down a step (22/800→600, 19/800→700, 25/700→600). The onboarding heroes kept their weight deliberately: they are a front door, not a room you live in.
>
> **Written down after the fact, and then written down wrong.** The first attempt at this section replaced four false claims with three new ones — asserting that nothing in the running app wears ExtraBold, that 12pt was the micro-label floor, and that 10pt was the absolute floor. All three were contradicted by code this same branch had shipped. A spec that asserts things the code doesn't do is worse than a spec that stays silent, because the next reader "fixes" the code to match it. **Describe what the code does; change the code first if you want a different sentence here.**

## 4. Motion & haptics

Three springs, defined once: `.plPop` (0.32/0.55 — icon and reaction bounce, the canvas's `cubic-bezier(0.34,1.56,0.64,1)`), `.plSnap` (0.28/0.75 — state changes), `.plSettle` (0.55/0.8 — arrivals). Haptics: light on chrome taps, medium when a plate lands, `.success` when the kiss is earned.

## 5. Structure

- Tab IA: **Plan · Table · + · Recipes · Home** in a floating 68pt capsule; active item ink, others faint; + is tomato, 54pt, rotates 90° on press. Four tabs and the +, symmetric 2 | + | 2.
- **Two floating objects, not one.** Prongsby is no longer a tab — six footer items was too crowded. He rides as a **perch**: one puck drawn once in the shell above the bar, inherited by every tab and every page pushed inside one, opening him as a sheet. A page that docks its own bottom control calls `.hidesProngsbyPerch()` (PostThreadView, RecipeDetailView) or the perch sits on that control.
- **Bottom spacing is a token family, never a typed number** (`Layout`, Theme.swift): `tabBarInset` (84) clears the bar alone — what a page that hides the perch needs; `perchBottom` (= tabBarInset) is where the perch sits; `perchHeight` (50); `floatingChromeInset` (perchBottom + perchHeight + 8) is what a scroll owes at its bottom. Derived from each other on purpose: a hand-written copy drifted short of the chrome it was meant to clear, and a hand-written 92 put a send button underneath the perch.
- Home: the household itself — masthead (HOUSEHOLD / the name), banner photo cropped to faces at pick time, the count, who sits at the table, who cooks when. Stats and badges live one tap in.
- **The count**: numbers carry no box and no glyph — number over word, hairline rules between, sentence case. A count that needs an icon to be legible has the wrong label, and a box around a number reads as a button that isn't one. One shared atom (`CountBlock`) across Home, the stats shelf and a person's profile.
- **Badges** are a medal grid, never full-width rows. One ring carries every state: it fills as the household climbs and a closed ring means earned, so nothing draws a lock or a tick. Prose lives in the tap, and a "closest badge" card puts the nearest goal on top.
- Plan (home): rolling next-7-nights, tonight first with 1.5pt ink border; open nights are dashed rows that expand into Pick for me / Cookbook / Ask the table; conic progress ring "N of 7 plated"; grocery is a basket in the header (of the plan, not a destination).
- Table: private invite-only feed; plate reactions; **10 plates = chef's kiss**; comments allow URLs (link chips).
- Discover: behind the search glass, which now sits **beside the feed's scope picker** rather than in the Table header — scoping the feed and searching it are the same kind of act, and the header has the host's own avatar to seat instead. A 2-col rounded-rect grid of dinners from tables that chose to be open. View-only from outside; plating and "save to cookbook" work; nothing about your table leaks outward. Kiss badges (sparkle-in-circle) mark ≥10-plate dishes.
- All tap targets ≥ 44pt. Sheets use `presentationCornerRadius(28)` and solid canvas backgrounds.

## 6. Widgets

Home-screen widgets are the register at postage-stamp size: canvas background, micro-label ("TONIGHT"), the dish photo as a circle, person-tinted cook dots, dashed circles for open nights. No tomato *accents* on the home screen — the widget's only job is the photo and the facts; person tints are identity, not accent, so a tomato-person's cook dot is fine. Type is Plus Jakarta Sans (bundled in the appex); Gabarito stays in the app — nothing in a widget reaches display scale. Widgets follow the *system* appearance (the home screen is the system's room); the pocket palette in `PlatedWidgets.swift` mirrors the app tokens light and dark. A snapshot older than its written day rolls forward honestly: passed days drop off, tonight goes empty rather than stale.

## 7. Roadmap register notes

Phase 3 (widgets, App Intents, app-group bridge, CloudKit sharing scaffold, onboarding invites) shipped. The gamification/insights surface shipped 2026-08-22 — the count on Home, the stats shelf, and the badge grid. Prongsby's on-device mind (Apple Foundation Models, with a rule-brain fallback) and "Ask Prongsby" via Siri shipped alongside it.

Next: live CKShare Tables once a signing team is wired; seat management UI; in-app purchases (held deliberately — `PlatedPlus.gatingEnabled` is the single constant that re-arms the seat gate and the Settings row when Nate calls it); a **sync-status affordance**, which is where broken CloudKit setup should surface — the pull-to-refresh deliberately does not report it, see `CloudSync.observeImports`; and moving **authorship from a stored name string to a relationship**, which is the real fix for renames orphaning a person's posts (`HouseholdIdentity.rename` is the interim door).
