# Plated — Design Specification v1.0

The single source of truth for Plated's visual and interaction design. Every value below is a decision, not a suggestion. iOS 18+, SwiftUI, no third-party UI libraries, no licensed fonts.

**The idea in one sentence:** Ramp's editorial restraint (warm paper, warm near-black ink, hairlines instead of shadows, one rationed accent, hierarchy by size not weight) fused with a cookbook's warmth (New York serif display, cream canvas, food-derived color, photography as the only decoration).

---

## 1. Design principles

- **The week is a home, not a database.** The Plan screen must survive the "login-page test": delete everything but today's meal, one serif headline, and one accent action — it should still work. Structure is whispered (hairlines ≤ 10% opacity, no boxes-in-boxes); content is spoken (photos, serif titles).
- **One accent, rationed.** Tomato appears only on the primary action and "live" moments (cook-now, active timer, tonight's slot marker). Never decoratively, never on two things at once on a screen. Everything else is ink, ink-secondary, hairline.
- **Two voices, strictly cast.** New York serif for food and editorial moments (recipe titles, day names, big stats, greetings). SF Pro for every functional element (buttons, labels, metadata, tab bar). A serif button is a firing offense.
- **Photography is the color system.** Recipe photos are full-color, rounded, chrome-free. The UI around them is a quiet cream stage. No gray scrims over food, no desaturation in dark mode.
- **Empty slots invite; they never nag.** A blank Thursday is an open dinner reservation — dashed outline, warm copy, one-tap "Pick for me." No badges, no red counts, no "0 meals planned."
- **Numbers behave like instruments.** Every mutable digit is tabular (`.monospacedDigit()`) and rolls with `.numericText`. Servings, timers, grocery counts, stats — nothing jitters, nothing pops.
- **Motion is spring-only punctuation.** Three named springs for the whole app; haptics fire only on completed user actions. If a screen has more than one celebratory animation, one of them is wrong.

---

## 2. Final palette

Warm-shifted throughout — no pure neutrals except white cards in light mode. All views reference semantic names only; hex lives in one tokens file.

### Core

| Token | Light | Dark | Role |
|---|---|---|---|
| `canvas` | `#FAF5EC` | `#191511` | App background. Never pure white/black. |
| `card` | `#FFFFFF` | `#231E18` | Elevated cards, sheets. Dark elevation = this lightness step, not shadow. |
| `ink` | `#2C241C` | `#F3EDE3` | Primary text. 14.1:1 / 15.6:1 on canvas (AAA). |
| `inkSecondary` | `#6E6459` | `#A99E90` | Metadata, captions. 5.3:1 / 6.9:1 (AA). |
| `inkTertiary` | `#9C9184` | `#6B6157` | Placeholders, checked-off items, past days. ~3:1 — never for essential text. |
| `hairline` | `#E9E1D3` | `#372F26` | All borders and dividers, 1px (`1/displayScale` in strokes). |
| `accent` (Tomato) | `#BE3A2B` | `#E5765F` | THE accent. Primary CTA, live cook state, links, selection. White text on light-mode tomato: 5.5:1. Dark-mode text on charred tomato: use `ink`-dark. |

### Slot accents (tags, dots, tint washes only — never large fills)

| Slot | Light | Dark | Notes |
|---|---|---|---|
| Breakfast (Honey) | `#B47816` | `#E7B75C` | Light mode: icons and ≥17pt text only (3.4:1). |
| Lunch (Basil) | `#5F7A3D` | `#9DB268` | 4.5:1 / 7.8:1. |
| Snack (Copper) | `#A5622F` | `#D9A054` | Browner than honey, duller than tomato — reads distinct at chip size. |
| Dinner (Mulled Wine) | `#8E4A54` | `#C98392` | 5.9:1 / 6.2:1. |

Chip formula (Cron-style tone-on-tone, never saturated fill + white text): background = `slotColor.mix(with: .canvas, by: 0.88)` (a 12% tint wash), text/icon = the full slot color. In dark mode: `slotColor.mix(with: .card, by: 0.80)` wash, slot color text.

### Semantic

| Token | Light | Dark | Role |
|---|---|---|---|
| `warning` | `#B45309` | `#F0A24F` | Dietary conflicts, expiring ingredients. 4.6:1 on light canvas. Always icon (`exclamationmark.triangle`) + tinted wash pill + label — never a bare dot, so it can't be confused with slot colors. |
| `success` | `#3E6B4A` | `#7FA98B` | List complete, recipe saved, week fully planned. Used at most once per flow. |

Derived states via iOS 18 `Color.mix` in perceptual space — no hand-authored shades: pressed = `.mix(with: .black, by: 0.12)`; washes = `.mix(with: .canvas, by: 0.88)`.

---

## 3. Typography system

Display = **New York** via `.fontDesign(.serif)` (free, optically sized, Dynamic-Type-native). UI = **SF Pro**. All sizes via text styles or `Font.custom(_:size:relativeTo:)` — never frozen `Font.system(size:)`.

| Role | Spec |
|---|---|
| **Hero title** ("Tonight", greeting) | New York 34pt semibold, tracking −0.5, `ink`. `relativeTo: .largeTitle`. |
| **Screen title** (Recipes, Grocery…) | New York 28pt semibold, tracking −0.3. `relativeTo: .title`. |
| **Section header / eyebrow** | SF Pro 12pt semibold, UPPERCASE, tracking +1.2, `inkSecondary`. ("THIS WEEK", "PRODUCE", "SATURDAY · GATHERING") |
| **Card title** (recipe names) | New York 20pt semibold, tracking −0.2. `relativeTo: .title3`. |
| **Body** | SF Pro 17pt regular, `ink`. Secondary rows same size, `inkSecondary` — weight/color contrast, not size shrinking. |
| **Caption / metadata** | SF Pro 13pt regular, `inkSecondary`; micro-labels 11pt medium. |
| **Big stat numerals** (Insights) | New York 40pt semibold, tracking −1, `.monospacedDigit()`, `ink`. Unit label beneath in eyebrow style. |
| **Inline mutable numbers** (servings, counts, timers) | SF Pro at context size, `.semibold.monospacedDigit()` + `.contentTransition(.numericText(value:))`. |

Rules: display-to-eyebrow scale contrast ≥ 4:1 (34/12 ≈ 2.8 in points but with serif-vs-caps voice contrast — hold this floor, never compress it). Never track body text. Ingredient lines get semantic typography: quantity+unit semibold, ingredient regular, prep notes ("finely chopped") in `inkSecondary`. Cap Dynamic Type surgically (`...accessibility2`) only on the week strip; use `ViewThatFits` everywhere else.

---

## 4. Component recipes

**Global card recipe** (basis for everything below): `card` fill, continuous corners always (`.clipShape(.rect(cornerRadius:style:.continuous))`), hairline `strokeBorder(hairline, lineWidth: 1/displayScale)`, shadows two-layer and faint — ambient `black 6%, r20, y8` + contact `black 5%, r2, y1` — light mode only; dark mode elevation = surface step + `white.opacity(0.06)` inner hairline. Nested radii are concentric: inner = outer − inset.

### Day card (week plan — Today)
- Radius 20 continuous, full-width minus 20pt screen margins.
- Photo-forward: 16:10 image top (radius 16 inside 4pt inset), eased 5-stop black scrim (0%@0.45 → 45%@1.0) behind text.
- Overlaid: eyebrow "TONIGHT" in white 90%, recipe title New York 24pt semibold white, one metadata chip ("35 MIN" — `.ultraThinMaterial` capsule, 11pt medium).
- Below photo (16pt padding): slot chips row for the day's other meals.
- Whole card is a Button, pressed scale 0.985.

### Day card (rest of week — compact row)
- Radius 16, height ~76pt, 16pt internal padding, hairline + contact shadow only (no ambient).
- Left: day block, 44pt wide — weekday eyebrow ("THU") + date numeral New York 20pt, `.monospacedDigit()`.
- Middle: dinner title SF 17pt semibold + slot dots (6pt circles in slot colors) for planned meals.
- Right: 48×48 photo thumbnail, radius 10, or nothing if empty.
- Past days: entire row at `inkTertiary`, thin strikethrough on title, small `checkmark` — the week becomes a quiet diary.
- **Empty variant:** dashed hairline border (no fill, no shadow), "What's for Thursday?" in `inkSecondary` 15pt, two text buttons inline: **Pick for me** (accent) · Browse (`inkSecondary`). No icons, no badges.

### Meal chip (slot tag)
- Capsule, tone-on-tone: 12% slot-color wash fill, slot-color text/icon, 11pt medium, padding 10×5, no border. Radius = capsule. Tap expands to the meal row in place via `matchedGeometryEffect`.

### Suggestion hero banner ("Pick for me" / weather-aware)
- Sits directly under the Today card. Radius 16, `canvas`-toned wash fill (`accent.mix(with:.canvas, by:0.94)` — a 6% tomato warmth), hairline border, **no shadow** (it's an invitation, not an object).
- Left: 13pt SF text, two lines max — "Rainy Tuesday. Braise something." in `ink`, source recipe name in `inkSecondary`.
- Right: text button "Add to plan" in accent, 15pt semibold.
- Dismissible by swipe; never reappears the same day.

### Recipe card (library grid)
- 2-up grid, 12pt gutters. Radius 16, image 4:3 full-bleed top (concentric 16 outside/16 top only via `UnevenRoundedRectangle`), 12pt padding below.
- Title: New York 17pt semibold, 2-line max. Metadata line: SF 12pt `inkSecondary` — "40 min · Serves 4", digits tabular.
- `.matchedTransitionSource` + `.navigationTransition(.zoom)` into detail. `.contextMenu` with preview.

### Grocery row + checkbox
- Rows in aisle sections; section = eyebrow header ("PRODUCE") + card container, radius 16, rows 52pt, hairline separators inset 16pt leading.
- **Checkbox (the signature interaction):** 26pt circle, 1.5pt `inkSecondary.opacity(0.4)` ring. On check: fill scales 0.001→1 with `.bouncy`, checkmark (white, caption bold) fades+scales in, label strikes through and fades to `inkTertiary`, `.sensoryFeedback(.impact(weight:.light, intensity:0.7))`. Fill color = `success` green.
- Checked rows slide (`.smooth`) into a collapsed "In cart (12)" group at bottom. Aisle complete: one `.success` haptic + one-shot phaseAnimator pop on the section header check. Header carries a small progress ring ("14 of 23") that animates every check — same ring motif reused on Plan ("5 of 7 dinners planned").
- Each item shows origin recipe as an 11pt `inkTertiary` suffix.

### Stat tile (Insights)
- Radius 16, `card` fill, standard card recipe, padding 16, min height 108.
- Eyebrow label top ("MEALS COOKED"), New York 40pt semibold numeral (`.monospacedDigit()`, `.numericText`), 12pt `inkSecondary` delta line ("+3 vs last week", digits tabular). Delta color: `success`/`inkSecondary` — never red for "down" (cooking less is not a failure).

### Section header
- Eyebrow spec (12pt semibold caps +1.2, `inkSecondary`), 24pt top margin, 10pt bottom, optional trailing text button in accent 13pt ("See all"). No disclosure chevrons, no icons.

### Primary button
- Height 52, radius 14 continuous, accent fill with `.gradient` (built-in whisper lighten), white text SF 17pt semibold (dark mode: `ink`-dark text on charred tomato), no border, no shadow, no uppercase.
- Pressed: scale 0.97 + fill `.mix(with:.black, by:0.12)`, `.snappy(duration:0.18)`.
- Secondary button: `ink.opacity(0.05)` fill, `ink` text, same geometry. One primary button per screen, maximum.

### Tab bar
- System `TabView`, iOS 18 `Tab` syntax, `.sidebarAdaptable` (this is the iPad story). `.tint(accent)`.
- Tabs: **Plan** `calendar` · **Recipes** `book.pages` · **Grocery** `checklist` · **Gatherings** `person.2` · **Insights** `chart.bar.xaxis`.
- `.background(.bar)` translucency intact — content scrolls under it. No custom bar in v1; the brand lives in content, not chrome. Symbols `.hierarchical`.

---

## 5. The Plan screen (home)

Opening Plated should feel like opening this week's menu at a restaurant you own. No calendar grid, no rows of settings-list cells: a single warm cream scroll where **tonight is the headline** and the rest of the week is the table of contents. The screen leads with a serif greeting and date eyebrow, then the Today card — big, photo-forward, the one place the eye lands. Weather-aware suggestion sits quietly beneath it as a one-line invitation, not a widget. The remaining days are compact rows that shrink as they recede into the future and gently gray as they pass — the week reads top-to-bottom as *tonight → soon → done*. Empty days are dashed invitations with "Pick for me." Nothing counts, nothing badges, nothing scolds.

```
┌─────────────────────────────────────┐
│ THURSDAY, AUGUST 21          (⊙ 5/7)│  eyebrow + week progress ring
│ Tonight                             │  New York 34pt semibold
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ [ full-bleed food photo       ] │ │  Today card, radius 20
│ │ [ scrim →                     ] │ │
│ │ [ TONIGHT        (35 MIN)     ] │ │  eyebrow + material chip
│ │ [ Miso-Butter Salmon          ] │ │  NY 24pt white
│ │  ◦breakfast ◦lunch chips row    │ │  slot chips, tone-on-tone
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ Rainy evening. Braise something.│ │  suggestion banner, 6% wash
│ │ Short Ribs        Add to plan → │ │
│ └─────────────────────────────────┘ │
│                                     │
│ THIS WEEK                           │  eyebrow
│ ┌ FRI 22 │ Chicken Tinga    [img] ┐ │  compact rows, 76pt
│ ┌ SAT 23 │ ⋯ dashed ⋯             ┐ │
│ │  What's for Saturday?           │ │
│ │  Pick for me  ·  Browse         │ │
│ └─────────────────────────────────┘ │
│ ┌ SUN 24 │ Gathering · Paella  ●● ┐ │  gathering badge = wine dot pair
│ ┌ M̶O̶N̶ ̶1̶8̶ │ ✓ done rows (past)     ┐ │  inkTertiary, at bottom
│                                     │
│  [Plan] Recipes Grocery Gath. Ins.  │
└─────────────────────────────────────┘
```

Interactions: pull down past the greeting stretches the Today photo (`visualEffect` stretch/parallax). Scrolling past ~220pt fades in a compact `.bar` header with the week range (`.onScrollGeometryChange`, `.smooth(0.25)`). Drag a recipe from a "Want to cook" tray (context menu on the + toolbar button) onto any day row — spring drop + `.selection` haptic. Tapping any day row expands it in place (`matchedGeometryEffect`) to show all four slots.

---

## 6. Motion & haptics

**Three named springs — the only animations in the codebase:**

| Token | Value | Used for |
|---|---|---|
| `.appSnappy` | `.snappy(duration: 0.25)` | Controls, selection, toggles, chip taps, pressed-state release, numericText ticks |
| `.appSmooth` | `.smooth(duration: 0.35)` | Layout changes, header collapse, sheet content, list reordering, skeleton cross-fade, row slide-to-cart |
| `.appBouncy` | `.bouncy(duration: 0.45, extraBounce: 0.1)` | Celebration only: grocery check-off, recipe-added-to-plan drop |

No `easeInOut` anywhere. Never animate on scroll position except the sanctioned `scrollTransition` card entrance (opacity 0.4→1, scale 0.94→1 — nothing bigger).

**Hero moves:** iOS 18 `.zoom` navigation transition on recipe card → detail (both tabs). `matchedGeometryEffect` for in-place morphs (day row expand, segmented selection capsule). `.transition(.blurReplace)` for all view swaps. `.contentTransition(.symbolEffect(.replace))` for icon state (heart fills).

**numericText everywhere digits change:** servings stepper, grocery count, progress ring label, stat tiles, cook-mode timer. Always paired with `.monospacedDigit()` and driven inside `withAnimation(.appSnappy)`.

**Haptic map (punctuation, not narration):**

| Trigger | Feedback |
|---|---|
| Grocery item check | `.impact(weight: .light, intensity: 0.7)` |
| Aisle/list complete | `.success` (max once per flow) |
| Recipe dropped on a day | `.impact(weight: .medium)` |
| Day/segment selection | `.selection` |
| Servings stepper | `.increase` / `.decrease` |
| Cook-mode step advance | `.selection` |

Never on scroll, never on programmatic changes, never on appear. Respect `accessibilityReduceMotion`: swap springs for `.smooth` fades, skip phaseAnimator pops.

---

## 7. What to avoid

- **Default `List`/`Form` styling** — the Settings-app look is the anti-brand. `.scrollContentBackground(.hidden)` + canvas, or `LazyVStack` cards.
- **Default blue tint anywhere** — audit toggles, links, ProgressViews, text selection.
- **Bold-weight display type doing hierarchy's job.** Hierarchy = size + serif voice + alpha, per Ramp. Semibold is the ceiling.
- **Saturated slot colors as fills** with white text — always tone-on-tone tint washes.
- **One dark shadow** (`.shadow(radius: 4)`) — the 2014 tell. Two-layer faint recipe or hairline only.
- **Pure `#FFF`/`#000` canvas or raw hex in views** — semantic tokens only; dark mode is warmer, not inverted.
- **Circular corner style** sneaking in via `RoundedRectangle` defaults — pass `.continuous` explicitly; keep nested radii concentric.
- **Magic numbers** — spacing off the 4pt grid (4/8/12/16/20/24/32; margins 20, card padding 16), radii off the scale (10/14/16/20, sheets 28), one-off spring params.
- **Spinner-only loading** — redacted skeletons on real layout with shimmer; cross-fade with `.blurReplace`.
- **Nagging emptiness** — badges on Plan, red counts, "0 planned", generic `ContentUnavailableView` where a brand moment belongs. Every empty state: one warm sentence + one action.
- **Emoji as icons; scrims that gray the food; cropped shadows** (use `.scrollClipDisabled()`); **alerts for routine feedback**; **serif in buttons/body**; **haptics on everything**; **stretched-phone iPad layout** (`.sidebarAdaptable` is non-negotiable).
- **Fixed font sizes / `minimumScaleFactor` < 0.8** — text styles + `relativeTo:` + `@ScaledMetric`; `ViewThatFits` over truncation.

---

## Implementation order

1. Tokens file (colors, radii, spacing, springs, shadows, type styles) — everything hangs off it.
2. Typography system (serif display + eyebrow labels).
3. Global card recipe, applied everywhere.
4. Plan screen (Today card, compact rows, empty-state invitations).
5. Zoom transition on recipe cards.
6. Grocery check-off ToggleStyle with haptics — the interaction users remember.
7. numericText + monospacedDigit on all stats.
8. Skeletons, empty states, scroll garnish (parallax, header collapse) last.