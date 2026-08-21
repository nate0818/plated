# BUILD SHEET — Plated Home Screen, 4 Direction Mockups

## 0. Global rules (all four directions)

- **Frame:** `.screen { width:393px; height:852px; overflow:hidden; position:relative; }` — design to fit with NO scroll. Bottom nav floats inside the frame.
- **Status bar:** 44px mock at top — "9:41" left, signal/wifi/battery glyphs right, in the direction's primary text color, 15px/600.
- **Bottom nav (all directions):** 4 tabs — **Today (active on this screen), Recipes, Grocery, Family.** Inline SVG icons 24px, stroke 1.8, round caps/joins: Today = plate/bowl, Recipes = open book, Grocery = basket, Family = two figures. Labels 11px under icons. Direction-specific chrome below.
- **Photos:** real food JPEGs, square source. Circular crop = `border-radius:50%; aspect-ratio:1; object-fit:cover;`. Rounded-rect crop = `object-fit:cover` + direction radius. Never place text directly on a photo except over a scrim (Midnight Kitchen only). Same photo set in all four directions for comparability.
- **Shared sample data:** Family = "the Meadows," 4 members (2 adults, 2 kids). Today = **Friday.** Tonight's hero = **Lemon Butter Salmon** (25 min, Serves 4, rating 4.8, "Kids 4/4"). Week rail Sat–Thu: Pizza Night, Roast Chicken, Veggie Stir-fry, Tacos, Pasta Bolognese, Sheet-pan Gnocchi.
- **Fonts:** Google Fonts `<link>` per direction (URLs given). No Inter, Roboto, or Arial anywhere. Fallback stacks: display → `Georgia, serif` (Midnight) or `system-ui, sans-serif` (others); body → `system-ui, sans-serif`.
- **No blue anywhere.** Green is the only cool-adjacent hue permitted (health/plan semantics only).

---

## 1. FRESH MARKET — vibrant playful color-block

**Fonts:** `https://fonts.googleapis.com/css2?family=Baloo+2:wght@600;700;800&family=Nunito+Sans:wght@400;600;700;800&display=swap` — **Baloo 2** display (700/800), **Nunito Sans** body (400–800).

**Palette**
- Canvas: `#FFF6EC` (warm cream)
- Surfaces: white cards `#FFFFFF`; color-block cards in tomato `#FF5A3C`, mango `#FFB020`, basil `#3DA35D`, berry `#B95CF4`
- Text: ink `#2D1B12`, secondary `#7A6455`, on saturated blocks `#FFFFFF` (700 weight minimum)
- Accent strategy: **color-block per meal type** — breakfast = mango, lunch = basil, dinner = tomato, treats = berry. Dinner (tonight) owns the hero, so the hero card is tomato. One block color per module, never gradients.

**Radius:** hero card 28 / cards 24 / inner thumbs 18 / chips + buttons 999.

**Shadows:** cards `0 16px 32px rgba(120,60,20,0.18)` (warm, never black). Buttons are "squishy": filled pill + hard bottom edge `box-shadow: 0 4px 0 <color 20% darker>` (tomato btn edge `#D6401F`; white btn on tomato edge `rgba(0,0,0,0.15)`). Nav shadow `0 12px 24px rgba(45,27,18,0.35)`.

**Photos:** circular sticker cutouts — `border-radius:50%` + `border:6px solid #FFF6EC` ring + warm card shadow — deliberately **overlapping card edges** (hero cutout hangs 76px above its card). Week thumbs 64px with 4px ring in that day's meal-type color.

**Chips:** height 32, radius 999, padding 0 14px, Nunito Sans 12/700. Meta chips = white bg, ink text, leading glyph allowed as literal copy (clock SVG or emoji per copy spec). Category chips = 14% tint of block color (`tomato tint #FFE6E0`, `mango #FFF1D6`, `basil #E2F1E6`, `berry #F3E6FB`) with full-strength color text. Active chip = block color fill, white text.

**Layout top→bottom** (side padding 24):
1. Status bar 44, ink.
2. Greeting row 56: "Hey, Meadows!" Baloo 2 26/800 ink (copy includes the fried-egg emoji "🍳"); right, 40px avatar circle with 3px mango ring.
3. **Tonight hero** (zone 372): tomato `#FF5A3C` card 345×296, radius 28; 180px circular salmon cutout centered, overlapping top edge by 76px, 6px cream ring; SIGNATURE starburst (spec below) overlapping cutout's lower-left; inside card: "TONIGHT" 11/800 white letterspace 0.1em → title "Lemon Butter Salmon" Baloo 2 28/800 white → chip row (white chips): "25 min" · "Kids 4/4" · "Easy" → full-width 48px white pill "Start cooking", tomato text 15/800, squishy edge.
4. **Week rail** 174: "This week" Baloo 2 20/700 ink + horizontal scroll of 7 cards 96×128, radius 20, white, gap 10: day letter 12/800 secondary, 64px circular thumb (4px meal-color ring), meal name 11/700 ink 2-line. Today (FRI) card = mango tint `#FFF1D6` bg + 2px `#FFB020` border.
5. **Suggestion** 84: basil `#3DA35D` card 345×84, radius 24: "Stuck for Thursday?" Baloo 2 18/700 white + white pill button "Spin ideas" basil text 13/800, squishy edge.
6. **Bottom nav:** floating pill 345×68, bottom:16, bg ink `#2D1B12`, radius 999; active tab = mango `#FFB020` pill (icon+label ink), inactive icons cream at 60% opacity.

**SIGNATURE — "Tonight's plate" starburst sticker:** 92px mango `#FFB020` starburst, `transform: rotate(-8deg)`, 3px cream ring, ink text Baloo 2 13/800 centered ("FRI-YAY!"), absolutely positioned overlapping the hero cutout like a fridge-magnet price sticker. `clip-path: polygon(50% 0%, 59% 12%, 72% 5%, 75% 19%, 90% 18%, 86% 32%, 100% 38%, 90% 50%, 100% 62%, 86% 68%, 90% 82%, 75% 81%, 72% 95%, 59% 88%, 50% 100%, 41% 88%, 28% 95%, 25% 81%, 10% 82%, 14% 68%, 0% 62%, 10% 50%, 0% 38%, 14% 32%, 10% 18%, 25% 19%, 28% 5%, 41% 12%)`.

---

## 2. MIDNIGHT KITCHEN — dark premium photographic

**Fonts:** `https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,400..600;1,9..144,400..600&family=Manrope:wght@400;500;600;700&display=swap` — **Fraunces** display (500/600, italics for dish names), **Manrope** body (400–700, all numerals).

**Palette**
- Canvas: `#191412` (warm espresso-black — never blue-black)
- Surfaces: cards `#241D19`, elevated `#2A2320`, hairline border `rgba(255,255,255,0.07)`
- Text: primary `#F5EFE6`, secondary `#B9AC9D`, tertiary `#7E7266`
- Accent strategy: **one metallic accent, saffron `#E8A33D`** — permitted ONLY on: primary CTA, star ratings, active nav state, one italic word in the greeting, "today" border. Ember tone `#4A2A16` reserved for the signature gradient. Nothing else gets color; the photography is the color.

**Radius:** hero 24 / cards 20 / thumbs 16 / chips + buttons 999.

**Shadows:** `0 16px 40px rgba(0,0,0,0.55)` on hero; every card gets `border:1px solid rgba(255,255,255,0.06)`. Frosted overlays (nav): `background:rgba(36,29,25,0.72); backdrop-filter:blur(16px)`.

**Photos:** full-bleed rounded-rect cards — the photo IS the surface. Bottom scrim on hero: `linear-gradient(180deg, rgba(25,20,18,0) 45%, rgba(25,20,18,0.92) 100%)`; all text sits in the scrimmed lower third. Week-rail thumbs: 56px circles with `border:1px solid rgba(255,255,255,0.12)`. No sticker rings, no rotation — everything plumb and quiet.

**Chips:** outline pills — transparent bg, `border:1px solid rgba(255,255,255,0.28)`, text `#F5EFE6` Manrope 12/500, height 28, padding 0 12px, radius 999. Star chip: saffron star glyph + `4.8`. Active/selected chip = saffron fill, `#191412` text.

**Layout top→bottom** (side padding 20):
1. Status bar 44, `#F5EFE6`, sitting on the ember gradient (signature, below).
2. Greeting 60: "Good evening, Nate" Fraunces 24/500 in `#F5EFE6` with "evening" in italic saffron; right, 36px avatar with 1px saffron ring.
3. **Tonight hero** 420: photo card 353×420, radius 24, full-bleed salmon photo + scrim. Lower third: overline "TONIGHT · 7:00" Manrope 11/700 letterspace 0.12em saffron → title "Lemon Butter Salmon" Fraunces italic 30/500 `#F5EFE6` → outline-chip row: "45 min" · "Serves 4" · "★ 4.8" → full-width 48px saffron pill "Start cooking", `#191412` text Manrope 15/700.
4. **Week rail** 124: header row — "Your week" Fraunces 20/500 + "Edit" Manrope 13/600 saffron right-aligned; horizontal scroll of cards 132×76, `#241D19`, radius 20, hairline border: 56px circular thumb left, right column = "SAT" 10/700 tertiary + meal name 13/500 primary 2-line. Today's card border `1px solid #E8A33D`.
5. **Suggestion** 92: card 353×92 `#241D19`, radius 20: 56px circle thumb + "Chef's pick for Saturday" Manrope 11/700 tertiary over "Charred Broccolini Pizza" 14/600 primary + outline chip "Swap" right.
6. **Bottom nav:** floating pill 353×64, bottom:16, frosted recipe above, radius 999, hairline border; active tab icon+label saffron, inactive `#7E7266`.

**SIGNATURE — Ember gradient hero:** the top 260px of the screen carries `background: linear-gradient(180deg, #4A2A16 0%, rgba(25,20,18,0) 260px)` behind status bar and greeting — the hero photo's warmth "bleeding upward" Spotify-style (fixed hand-picked tone, no runtime extraction). The greeting floats in warm ember light; the page cools to espresso below.

---

## 3. SOFT CLUB — airy dribbble-core modern

**Fonts:** `https://fonts.googleapis.com/css2?family=Gabarito:wght@500..900&family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap` — **Gabarito** display (700/800), **Plus Jakarta Sans** body (400–600).

**Palette**
- Canvas: `#FAF7F2` (warm off-white)
- Surfaces: cards `#FFFFFF` with `border:1px solid #EFE9E1`; divider `#EFE9E1`
- Text: primary `#1E1B16`, secondary `#8A8074`, tertiary `#B5AC9E`
- Accent strategy: **two-accent split** — herb green `#4C9A62` = plan/health actions + active states (date pill, nav, "Fill my week"); apricot `#F2994A` = appetite actions only ("Cook now", add-to-plan). Tints: green tint `#EDF5EF`, apricot tint `#FEF3E9`. Tint text: green-dark `#37744A`, apricot-dark `#C0722E`. Nothing else is colored.

**Radius:** cards 24 / photo rects 20 / inner 16 / chips + buttons 999.

**Shadows:** plates `0 20px 40px rgba(130,80,40,0.15)`; cards `0 8px 24px rgba(130,80,40,0.08)` + the 1px border; nav `0 12px 32px rgba(60,45,30,0.14)`. All warm-tinted, never gray-black.

**Photos:** circular cutouts, NO ring, warm shadow, top-down angle — plates sitting on a counter. Hero cutout 192px sits **half out of the top** of its white card (card `margin-top:96px`, image absolute `top:-96px`). Rail plates 80px casting shadows directly on the canvas (no card behind them).

**Chips:** meta chips height 30, radius 999, padding 0 12px, PJS 13/600, tint bg + dark-accent text ("25 min" and "★ 4.8" in apricot tint, "Balanced" in green tint). Date pills: 44×60 vertical, radius 999, white + border, day letter 11/600 secondary over date number 16/700 ink; today = `#4C9A62` fill, white text, no border.

**Layout top→bottom** (side padding 24):
1. Status bar 44, ink.
2. Greeting 72: "GOOD MORNING" PJS 12/600 letterspace 0.08em secondary, over "What's cooking, Meadows?" Gabarito 26/800 ink; right, 44px avatar.
3. **Date strip** 60: 7 date pills, gap 8, FRI filled green.
4. **Tonight hero** (zone 328): white card 345×232, radius 24; 192px salmon plate half-out the top; inside: green-tint chip "Tonight" → "Lemon Butter Salmon" Gabarito 24/700 ink centered → chip row: "25 min" · "Balanced" · "★ 4.8" → button row: apricot `#F2994A` pill 48px "Cook now" white 15/700 + ghost pill "Swap" (1px `#EFE9E1` border, ink text).
5. **Week rail — SIGNATURE floating plate carousel** 138: "This week" Gabarito 18/700 + horizontal scroll of 7 bare 80px circular plates, gap 20, each casting the plate shadow straight onto the cream canvas, meal name 12/600 secondary centered beneath; today's plate gets `outline:2px solid #4C9A62; outline-offset:3px`.
6. **Suggestion** 84: green-tint `#EDF5EF` card 345×84, radius 24, no border: "3 dinners still unplanned" PJS 14/600 green-dark + green `#4C9A62` filled pill "Fill my week ✨" white 13/700 (sparkle = the AI hook).
7. **Bottom nav:** floating white pill 345×68, bottom:16, border + nav shadow, radius 999; active tab = green `#4C9A62` pill around icon+label in white; inactive `#8A8074`.

**SIGNATURE — the floating plate carousel** (item 5): the week rendered as physical plates set out on a counter — no cards, no frames, just circles + warm shadows on cream. It IS the week rail; do not wrap it in a container.

---

## 4. FRIDGE DOOR — wildcard collage / sticker / tactile

**Fonts:** `https://fonts.googleapis.com/css2?family=Caprasimo&family=Karla:wght@400;500;700&family=Caveat:wght@500;600&display=swap` — **Caprasimo** display (400 only), **Karla** body (400–700), **Caveat** for handwritten annotations ONLY (captions, notes — never UI labels).

**Palette**
- Canvas: kraft `#E9DCC8` + grain overlay: `background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='120' height='120'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2'/><feColorMatrix values='0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.04 0'/></filter><rect width='120' height='120' filter='url(%23n)'/></svg>")` tiled.
- Surfaces: note/polaroid white `#FFFDF7`, sticky note `#F7E58B`
- Text: ink `#2E2318`; Caveat annotations in ink or ketchup only
- Crayon palette (functional, not decorative): ketchup `#E0452C`, mustard `#E8B93E`, pea `#6FA84C`, grape `#7B5BA6`. **Magnets = family-member assignment** (Nate=ketchup, partner=mustard, kid1=pea, kid2=grape). **Washi tape = pinned meal.**

**Radius:** note cards 6 / polaroid 4 / stickers + magnets 50% / pills 999. Every paper element rotated between −6° and +6° (alternate signs; nav stays at 0°).

**Shadows:** ALL hard, no blur — stickers `0 3px 0 rgba(0,0,0,0.2)`; paper `2px 5px 0 rgba(60,42,20,0.15)`; buttons `0 4px 0 <30% darker>`; nav `0 5px 0 rgba(60,42,20,0.18)`.

**Photos:** die-cut stickers — circular crop + `border:5px solid #FFFFFF` + hard sticker shadow + rotation. Hero uses a **polaroid**: white frame, 8px padding sides/top, 44px bottom for a Caveat caption, photo inside at 4px radius.

**Component recipes:** washi tape = 64×22 rect, crayon color at 82% opacity, `rotate(±6deg)`, overlapping the parent's top edge. Magnet = 16px circle, `background:radial-gradient(circle at 35% 30%, <color +25% lighter>, <color>)` (ketchup: `#FF7A5C → #E0452C`). Gold star = 34px mustard shape, `clip-path:polygon(50% 0%, 61% 35%, 98% 35%, 68% 57%, 79% 91%, 50% 70%, 21% 91%, 32% 57%, 2% 35%, 39% 35%)`. Torn note top edge: `clip-path:polygon(0 6px, 8% 0, 16% 5px, 25% 1px, 34% 6px, 43% 0, 52% 5px, 61% 1px, 70% 6px, 79% 0, 88% 4px, 100% 2px, 100% 100%, 0 100%)`.

**Chips ("label stickers"):** white pill, height 28, `border:1.5px solid #2E2318`, radius 999, Karla 11/700 UPPERCASE letterspace 0.06em ink, each rotated ±2°.

**Layout top→bottom** (side padding 20; elements may overlap edges deliberately):
1. Status bar 44, ink.
2. Greeting 72: torn white note ~230×60, `rotate(-2deg)`, hard paper shadow, mustard tape top-center: "Meadows family menu" Caveat 22/600 ink; right of it, the 4 family magnet dots in a vertical stagger.
3. **Tonight hero** (zone 360): polaroid 300×330 centered, `rotate(1.5deg)`, mustard tape both top corners: salmon photo 284×230 → Caveat caption 20 "salmon night!!" ink → label-sticker chip row: "25 MIN" · "EASY" · "DAD COOKS" (ketchup magnet dot butted against that chip) → ketchup pill button "Let's cook" white Karla 15/700, hard edge `0 4px 0 #B23319`.
4. **Week rail — SIGNATURE magnet board** 116: 7 die-cut sticker meals 72px in horizontal scroll, gap 14, stuck straight onto the kraft canvas; each has a 14px assignee magnet overlapping its top edge; day label Caprasimo 12 ink beneath; **Friday wears the gold-star sticker** overlapping its lower-right ("kids' fave"); Saturday is pinned with a pea washi strip instead of a magnet.
5. **Suggestion** 150: sticky note `#F7E58B` 168×140, `rotate(-3deg)`, hard paper shadow, left-placed: "need an idea for thurs?" Caveat 19/600 ink + "shuffle →" Karla 13/700 ketchup underline. Right of it: small torn note 140×96 `rotate(2deg)`: "grocery — 12 items" Karla 12/700 + pea magnet dot.
6. **Bottom nav:** bar 353×64, bottom:16, `#FFFDF7`, radius 20, `border:1.5px solid #2E2318`, hard nav shadow, rotation 0; labels Karla 11/700; active tab = ink icon + 8px ketchup magnet dot centered above it; inactive `#9C8C76`.

**SIGNATURE — the magnet-board week** (item 4): meals as physical stickers held to the fridge by color-coded family magnets and tape, with an earned gold star. The mechanic (magnet = who cooks, tape = pinned, star = kid-approved) is the direction's whole identity — keep all three visible in the mockup.

---

## Cross-direction QA checklist
- All four screens show the identical IA: greeting → tonight hero → week rail (7 items, FRI marked) → one suggestion module → 4-tab nav with Today active.
- No Inter/Roboto/Arial; no blue; no text on unscrimmed photos; no cool-gray shadows on light canvases.
- Circular crops everywhere except Midnight Kitchen hero (rounded-rect full-bleed) and Fridge Door polaroid (framed rect).
- Exactly one signature element per direction: starburst sticker / ember gradient / floating plate carousel / magnet board.