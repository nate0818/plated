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

- **Gabarito** (display): screen titles 25/700, hero lines 32/800, date numerals 19/800, sheet titles 19/800, splash 42/800. Negative tracking on large sizes (−0.3 to −1).
- **Plus Jakarta Sans** (everything else): body 14–15, chips/buttons 13/700, micro-labels 12/700 with +1.0 tracking, uppercase.
- Registered at launch via `CTFontManagerRegisterFontsForURL` from `Resources/Fonts`; use `Font.gabarito(_:_:)` / `Font.jakarta(_:_:)` only.

## 4. Motion & haptics

Three springs, defined once: `.plPop` (0.32/0.55 — icon and reaction bounce, the canvas's `cubic-bezier(0.34,1.56,0.64,1)`), `.plSnap` (0.28/0.75 — state changes), `.plSettle` (0.55/0.8 — arrivals). Haptics: light on chrome taps, medium when a plate lands, `.success` when the kiss is earned.

## 5. Structure

- Tab IA: **Week · Table · + · Recipes · Home** in a floating 68pt capsule; active item ink, others faint; + is tomato, 54pt, rotates 90° on press.
- Week (home): rolling next-7-nights, tonight first with 1.5pt ink border; open nights are dashed rows that expand into Pick for me / Cookbook / Ask the table; conic progress ring "N of 7 plated"; grocery is a basket in the header (of the plan, not a destination).
- Table: private invite-only feed; plate reactions; **10 plates = chef's kiss**; comments allow URLs (link chips).
- Discover: behind the search glass in the Table header — a 2-col rounded-rect grid of dinners from tables that chose to be open. View-only from outside; plating and "save to cookbook" work; nothing about your table leaks outward. Kiss badges (sparkle-in-circle) mark ≥10-plate dishes.
- All tap targets ≥ 44pt. Sheets use `presentationCornerRadius(28)` and solid canvas backgrounds.

## 6. Roadmap register notes

Phase 2 (Discover + After Dark) shipped. Phase 3 is the connective tissue: CloudKit sharing for real multi-household Tables, real seat invites from the pending-seats list, "what's for dinner" widgets, and App Intents.
