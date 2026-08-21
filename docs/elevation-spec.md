# Plated v2 — the award pass

**The call.** Merge verdict: the Plate direction wins the *object* — every piece of food in the app renders as a circular generative plated dish, and the circle becomes the state language (empty plate / plated / cleared). Editorial Maximal wins the *voice* — monumental New York mastheads, a third condensed-caps type voice, and one dark "ink field" band per screen meaning *done*. Rejected from Direction A: nothing. Rejected from Direction B: full-bleed rectangular art, text-set-on-art, and scrims (type never sits on art in this app — that permanently kills the mud problem), the 96pt-everywhere numerals, and the asymmetric magazine grid (the dish art is the variation; the grid stays calm). One sentence a juror can repeat: **in Plated, food lives on plates, and the type is the menu.**

Rules that hold everywhere: circles are food and state only; every container/tool is a continuous-corner rounded rect (Radius 14–20); tomato appears at most once per screen in content (system tab tint exempt); dark ink bands always mean "done/collected," never decoration; no text ever overlays art.

Execute top to bottom. All tokens/springs below are the existing ones in `/Users/natemeadows/Plated/Plated/Support/Theme.swift` unless marked NEW.

---

## 1. `DishView` — the generative plate art engine (all screens · ~5h · retints the entire app)

New file `/Users/natemeadows/Plated/Plated/Views/Components/DishView.swift`. Kills every brown LinearGradient and every `fork.knife`.

**Layer stack, for diameter D (outside-in):**
1. Porcelain: `Circle().fill(Color.cardFill)` at D, with the spec's two-layer shadow (ambient `.black.opacity(0.06), r20, y8` + contact `.black.opacity(0.05), r2, y1`; dark mode: no shadow, `white.opacity(0.06)` inner hairline).
2. Well ring: `Circle().strokeBorder(Color.hairline, lineWidth: 1/displayScale)` at 0.86 × D. Non-negotiable — this is what makes it read "plate," not "colored circle."
3. Food: 3×3 `MeshGradient` clipped to `Circle()` at 0.82 × D (porcelain rim ≈ 0.09 × D shows around the food).
4. Garnish: seeded `Canvas` marks, only when D ≥ 96.
5. Grain: `.layerEffect` noise shader over the food circle only, strength 0.05 (±2.5% luminance).

**Seed (deterministic — do NOT use `hashValue`, it's per-launch):** FNV-1a over `recipe.title.utf8` → `UInt64` seeding a `SplitMix64` RNG.

**Palette family — keyed by weather mood, overridden by title keywords.** Each family: `[deep, mid, bright]`, saturation 0.55–0.80, luminance spanning ~0.30→0.90 so every dish has a deep pool and a bright zone. Map `recipe.moods.first` (the existing `WeatherMood`):

| Mood | Family | deep / mid / bright |
|---|---|---|
| `.cold` | Ember & Braise | `#5C190D` / `#C7452B` / `#F2B279` |
| `.rainy` | Wine & Tomato | `#471522` / `#9E3547` / `#EDA47C` |
| `.cool` | Saffron & Roast | `#6E4210` / `#DD9C34` / `#F6E3B4` |
| `.mild` | Copper & Herb | `#4C3A1E` / `#A5622F` / `#E8D9A6` |
| `.warm` | Basil & Lemon | `#2E4B23` / `#6FA544` / `#EDE289` |
| `.hot` | Sea & Citrus | `#16455C` / `#3E8FA8` / `#F2DE8E` |
| `.grillWeather` | Char & Flame | `#3B2A22` / `#B4502A` / `#F4A259` |
| no mood (fallback) | Beet & Plum | `#3E1533` / `#8E3A68` / `#E7B3CB` |

Title/tag keyword override runs first (`chili|stew|braise`→Ember, `salad|green|herb|pesto`→Basil, `bolognese|ragù|pasta|tomato`→Wine, `fish|shrimp|ceviche`→Sea, `curry|rice|roast chicken`→Saffron, `grill|bbq|char`→Char, `beet|berry|plum`→Beet, `chocolate|bake|dessert`→Copper). **Adjacency rule:** in any grid/row, if a neighbor resolves to the same family, rotate the later one +3 through the family list.

**Mesh recipe, exactly:**
```swift
MeshGradient(width: 3, height: 3,
  points: base3x3.map { jitterInterior($0, by: rng, amount: 0.15) }, // corners stay pinned
  colors: shuffled(rng, [bright, bright, bright, mid, mid, mid, mid, deep, deep],
                   constraints: centerNeverBright, atLeastOneCornerBright))
```
Edge midpoints and center jitter ±0.15; corners fixed at 0/1. This yields organic pools with a guaranteed bright zone and deep zone per dish.

**Garnish:** 5–9 marks from the same RNG — three glyph types only (2pt-stroke arc 20–40pt, filled seed-ellipse 4–8pt, rotated leaf-ellipse 12–20pt), colored `deep` at 25% and `bright` at 35%, minimum spacing 0.18 × D, all inside 0.78 × D.

**Grain shader** (new `/Users/natemeadows/Plated/Plated/Support/Shaders.metal`):
```metal
[[ stitchable ]] half4 grain(float2 p, half4 c, float s) {
  float n = fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
  return half4(c.rgb + half3((n - 0.5) * s), c.a);
}
```

**`PlateState` (the state language, same file):** `.empty` = 1.5pt `inkSecondary.opacity(0.4)` circle + hairline well ring, no fill (an open evening); `.planned(Recipe)` = DishView; `.cleared` = porcelain + well ring + 9pt `checkmark` in `successTone` center (a cleared plate — replaces every strikethrough). All progress rings app-wide become plate rims filling in `successTone` — tomato never rings anything again.

**Size tiers (only these):** 16 (tally), 18 (origin), 26 (checkbox), 44 (week strip), 48 (day row), 140 (grid), 280 (Plan hero), 340 (detail). `drawingGroup()` at ≤140; garnish off below 96; exactly one animated mesh on screen ever. When real photos arrive they clip into the same 0.82 circle — the system survives success.

## 2. Kill the custom tab bar (all screens · ~1h · un-clips three screens)

`/Users/natemeadows/Plated/Plated/Views/ContentView.swift`: delete the floating pill entirely. System `TabView` with iOS 18 `Tab` syntax, `.tint(.tomato)`, `.sidebarAdaptable`, hierarchical symbol rendering. Plan tab icon = `circle.circle` (`circle.circle.fill` when tonight is planned) — the plate mark, free from SF Symbols. Delete every beige toolbar circle and the ‹ › chevron capsule app-wide; toolbar actions become bare 17pt hierarchical symbols in `ink`. Week paging moves to horizontal swipe (`.scrollTargetBehavior(.paging)`) + tappable date eyebrow.

## 3. Typography scale-up + the third voice (all screens · ~1.5h)

In `Theme.swift`:
- `masthead` NEW = NY 54pt semibold, tracking −1, `relativeTo: .largeTitle`, `ViewThatFits` fallback 44pt. Replaces `screenTitle`/`heroTitle` at the top of all five screens.
- `condensedEyebrow` NEW = SF Pro 12pt semibold, `.fontWidth(.condensed)`, UPPERCASE, tracking +1.5, `inkSecondary`. Replaces every eyebrow and metadata caps line ("60 MIN · SERVES 6", "PRODUCE — 3", "3 DISHES · 1 FAVORITE").
- `statNumeral` → 56pt (was 40), tracking −1.5, `.monospacedDigit()`.
- SF Rounded appears exactly once: 17pt semibold tabular numerals sitting next to plate glyphs (week-strip count, tally counts).
- Masthead composition on every screen: condensed eyebrow top-left, 54pt serif word below breaking left, one flush-right datum (Plan: 40pt `successTone` rim-ring "3 OF 7"; Recipes: "3 DISHES · 1 FAVORITE"; Grocery: 40pt ring "2 OF 8"; Insights: range control; Gatherings: "NEXT: SUN").

Add ink-field tokens NEW: `inkWell = Color(light: 0x241C14, dark: 0x100D0A)`, `inkWellText = #F3EDE3` (55% when struck), accent-on-ink always `#E5765F`.

## 4. Plan — the table setting (~4h)

`/Users/natemeadows/Plated/Plated/Views/WeekPlanView.swift`, top to bottom:
1. Masthead per item 3 ("FRIDAY, AUGUST 21" eyebrow · **Tonight** 54pt · ring flush-right).
2. **Hero: 280pt DishView centered directly on cream — no card, no scrim; the canvas is the tablecloth.** Below, centered: title NY 26pt semibold `ink`, 2-line `ViewThatFits` (truncation banned); one condensed metadata line "60 MIN · SERVES 6"; then the screen's single tomato element: "Start cooking" 17pt semibold text button. Whole cluster is a `Button` with `.matchedTransitionSource` → `.navigationTransition(.zoom)`.
3. **Week strip (the signature): seven 44pt `PlateState` plates, 8pt gaps**, 11pt condensed weekday initials beneath; tonight gets a 2pt tomato halo at 4pt offset (this halo + Start cooking count as the same "live tonight" accent moment). This strip is the future widget and app icon, verbatim.
4. Day rows (radius 16 cards, 76pt): day block left (condensed "SAT" + NY 20 tabular date), title 17pt semibold 2-line, **48pt DishView right**. Empty rows: no fill/shadow, dashed `StrokeStyle(lineWidth: 1, dash: [4,3])` in `hairline`, 44pt empty plate left, "What's for Sunday?" 15pt `inkSecondary`, inline **Pick for me** (tomato — only on the first empty day; later ones get `inkSecondary` for both) · Browse. The string "Nothing planned" is deleted from the codebase.
5. **Ink band (bottom): "EARLIER THIS WEEK"** — full-bleed `inkWell`, condensed cream eyebrow, past days as rows of 26pt cleared plates + titles in `inkWellText` 55%. Fix chronology: today first, future ascending, past only in this band.

## 5. Grocery — into the bag (~3h)

`/Users/natemeadows/Plated/Plated/Views/GroceryListView.swift`:
- Checkboxes become **26pt mini plates** (rim + well ring). On check: `successTone` mesh disc scales 0.001→1 with `.appBouncy`, white caption-bold check, `.sensoryFeedback(.impact(weight: .light, intensity: 0.7))`.
- **"In cart" becomes the ink band footer**: `inkWell` full-bleed, header "IN CART (2)" condensed cream — whole header the button, no chevron, count via `.contentTransition(.numericText())`; checked rows sit inside struck in `inkWellText` 55%. Checked row slides down across the paper/ink boundary with `.appSmooth`, recoloring mid-flight.
- Delete all section-header icons; aisle identity = 2pt slot-color tick (`basil`/`mulledWine`/`honey`/`copper`) on each section card's leading edge.
- Every row gains origin suffix: 18pt DishView + "· Weeknight Chili" 11pt condensed `inkTertiary`.
- Masthead ring 40pt `successTone`, rolls with `.numericText`. "Add an item": no card fill, dashed hairline, `inkTertiary` placeholder. Full list complete → ring closes, one `.success` haptic, serif toast **"Plated."** (once per flow).

## 6. Insights — the ledger and the tally (~2.5h)

`/Users/natemeadows/Plated/Plated/Views/InsightsView.swift`:
- Stats become a **ledger**: full-width hairline-ruled rows, NY 56pt numeral flush-left, condensed label flush-right, delta line tabular ("+2 VS PRIOR 90 DAYS") in `successTone`/`inkSecondary`. Delete the redundant MOST COOKED tile → "NEW DISHES TRIED".
- **Delete the Swift Charts bar chart entirely** (this deletes the axis-overshoot bug). Replace with plate tallies: per recipe — 32pt DishView, name 15pt, N × 16pt cleared-plate glyphs, count NY 20pt tabular trailing. Appears once with `.appSmooth`, 40ms left-to-right stagger.
- Delete every zero row ("Breakfast 0", "Lunch 0"). All-dinners case gets one serif line: "All dinners so far — breakfast is an open canvas."
- Range control: capsule track `ink.opacity(0.05)` h34, selected pill `cardFill` + contact shadow moved by `matchedGeometryEffect` with `.appSnappy`, labels SF 13pt medium. Kill the systemGray segmented control.

## 7. Recipes — the shelf (~2h)

`/Users/natemeadows/Plated/Plated/Views/RecipeLibraryView.swift`:
- Masthead first, search second (`.searchable` collapsing into the nav bar).
- Grid cells: **140pt DishView centered on a plain radius-16 `cardFill` card**, title NY 17pt semibold 2-line below, one condensed line "60 MIN · SERVES 6". Delete the "1×/3×" metadata. Adjacency rule guarantees neighbors differ. Favorite = 28pt `.ultraThinMaterial` circle on the card corner (never over the dish), 13pt heart, `.contentTransition(.symbolEffect(.replace))`.
- Final cell is always the invitation: empty plate + "Add a recipe" / "Paste a link", dashed grammar identical to Plan's empty days.
- `.matchedTransitionSource` + `.navigationTransition(.zoom)`: the dish zooms into `RecipeDetailView` at 340pt.

## 8. Gatherings — setting the table (~2h)

`/Users/natemeadows/Plated/Plated/Views/GatheringsView.swift` + `/Users/natemeadows/Plated/Plated/Support/SampleData.swift`:
- Fix the data bug: "Sunday Supper" moves to Sunday Aug 23 (Aug 24, 2026 is a Monday).
- Card: date block NY 44pt ("SUN / 23") left; menu = overlapping 56pt DishViews (−12pt spacing) + one empty plate ("add a course"); guests = overlapping 24pt initial circles in slot-color washes (`slotColor.mix(with: .canvas, by: 0.88)`). Eyebrow drops wine-red for condensed `inkSecondary`.
- The void becomes the warmest moment: 120pt empty plate flanked by two hairline Canvas fork/knife strokes, "Feeding people is the whole point." NY 20pt, "Plan a gathering" tomato text button.

## 9. Signature motion — one per screen, three springs only (~2.5h)

| Screen | The one moment | Recipe |
|---|---|---|
| Plan | **Plating**: picked recipe shrinks and lands on the day's empty plate — `matchedGeometryEffect`, `.appBouncy`, rim overshoot 1.06→1.0, `.impact(weight: .medium)`. Same choreography for Pick-for-me and gathering courses. | Ambient exception: hero mesh drifts two interior points ±0.03 on an 8s `TimelineView` sine — hero only. |
| Recipes | Dish zoom to detail (`.navigationTransition(.zoom)`) | |
| Grocery | Check-fill + slide into the ink band (`.appBouncy` then `.appSmooth`) | |
| Insights | One-shot tally stagger (`.appSmooth`, 40ms) | |
| Gatherings | Reuses Plating for adding a course — nothing new to learn | |

`accessibilityReduceMotion`: plating → `.smooth` cross-fade, sauce frozen, slides → fades.

## 10. Kill list (delete, do not restyle)

`fork.knife` (all 6+ instances) · every recipe `LinearGradient` · the custom pill tab bar · beige toolbar circles · the ‹ › chevron capsule · the string "Nothing planned" · scrims (no text on art anywhere) · the Swift Charts bar chart, its axis, its gridlines · "Breakfast 0 / Lunch 0" rows · the MOST COOKED stat tile · "1×" grid metadata · grocery section-header icons and the "In cart" chevron · the wine-red date eyebrow · the systemGray segmented control · every truncating single-line recipe title (2-line `ViewThatFits` everywhere).

---

## Definition of done — 8 screenshot assertions

1. **No mud, no clipart:** zero `fork.knife` glyphs and zero rectangular gradient art anywhere; every piece of food is a circular dish with a visible porcelain rim and inner well ring.
2. **Every dish is itself:** any two dishes visible together differ in palette family — chili reads ember-red, salad reads basil-green, bolognese reads wine — distinguishable at 44pt.
3. **Chrome:** system tab bar with tomato tint; Plan tab shows the plate mark (`circle.circle`); the last row of every scrollable screen is fully readable above the bar; no beige circle buttons anywhere.
4. **Plan fold (393×852):** eyebrow, "Tonight" ≥54pt serif, the 280pt plate, full untruncated title (no "…" anywhere in the app), "Start cooking," and all seven week-strip plates visible; days chronological; the words "Nothing planned" appear nowhere.
5. **Dark means done:** at most one ink-field band per screen (Plan past days, Grocery in-cart, Gatherings past), containing only completed/collected items in cream text — never decoration.
6. **Honest data:** Insights has no axes or gridlines; each tally's plate-glyph count equals its numeral; no zero-count row exists on any screen.
7. **Voice:** every screen opens with a condensed-caps eyebrow + one NY serif masthead ≥54pt + one flush-right datum; at most one tomato element in content per screen (tab tint exempt).
8. **Shape discipline:** every circle on screen is food, plate-state, a ring, or a guest initial; every button, card, chip, and input is a continuous-corner rounded rectangle (radius 10–28) — a circle anywhere else is a bug.