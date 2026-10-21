# Editorial: Plated design system

Selected October 16, 2026. See [the product contract](../DESIGN.md). The orange
primary CTA is the approved variation of the Editorial concept.

## Foundations

Newsreader Roman for titles; DM Sans for reading and controls. The default
Editorial appearance uses deep green `#191C17`, cream `#EFF0E6` text and sage
supporting accents, matching the selected concept. Light paper is optional in
Settings. Original Plated
orange for primary commits. Flat surfaces, fine rules, generous photo fields,
near-square photo corners, and small rectangular controls.

| Role | Optional Light | Default Editorial | Implementation |
| --- | --- | --- | --- |
| Paper | `#FAF9F4` | `#191C17` | `canvas` |
| Main ink | `#26382C` | `#EFF0E6` | `ink` |
| Supporting ink | `#606A57` | `#B4BEAA` | `inkSecondary` |
| Surface | `#EEEEE4` | `#24291F` | `fill` |
| Rule | `#DCE0D2` | `#384031` | `hairline` |
| Small supporting accents | `#365C43` | `#B7CAA5` | `olive`, `accentText` |
| On olive | `#FFFFFF` | `#182219` | `onOlive` |
| Primary CTA | `#F45132` | `#FF5738` | `primaryAction` |
| On primary | `#241D14` | `#241D14` | `onPrimary` |
| Destructive ink | `#A33D2D` | `#F0A595` | `dangerText` |

Code owns numeric values. Never spell out colors in a screen. A photograph's
scrim stays dark in both appearances. `inkFaint` carries no text. Identity-color
keys in stored membership data are preserved; they are not brand palette values.

Date and choice selections use `selectionFill` (`ink`) with `onSelection` (`canvas`) labels: cream and dark
text in Editorial, inverted in optional Light. Panels stay close to the canvas
with fine borders. Avoid broad pale green selection fills; keep olive accents
small. This matches the grocery controls and the shared SelectChip treatment.

Existing automatic-theme installs adopt Editorial once. An explicit Light
choice is preserved. After migration, later appearance selections persist.
Launch uses the deep green surface even when the phone is in Light Mode.

## Typography

| Scale | Base points | Family |
| --- | ---: | --- |
| micro | 11 | DM Sans |
| caption | 12 | DM Sans |
| footnote | 13 | DM Sans |
| body | 15 | DM Sans |
| callout | 16 | DM Sans |
| heading | 23 | Newsreader |
| title | 29 | Newsreader |
| display | 34 | Newsreader |
| hero | 40 | Newsreader |

`.plType` supplies tracking, leading and Dynamic Type. Newsreader display weights
resolve to regular/medium. Control emphasis caps at DM Sans semibold. Optical
cap-height matching uses the bundled font metrics, not the retired font family.
The wordmark is **Plated** in Newsreader, without the orange punctuation dot.

Both fonts are bundled for offline rendering. Sources and licenses:
[Newsreader](https://github.com/google/fonts/tree/main/ofl/newsreader) and
[DM Sans](https://github.com/google/fonts/tree/main/ofl/dmsans), SIL Open Font License.
License files ship beside the binaries. System camera, Apple sign-in and other
OS-owned interfaces retain their native fonts and controls.

## Layout tokens

| Token | Points | Role |
| --- | ---: | --- |
| Spacing.inline | 8 | Icon-label and related text |
| Spacing.compact | 12 | Related controls |
| Spacing.content | 16 | Component interior |
| Spacing.page | 24 | Phone page gutters |
| Spacing.section | 28 | Sections |
| ControlMetrics.minimumTarget | 44 | Minimum interactive width/height |
| ControlMetrics.primaryHeight | 48 | Minimum action height |
| ControlMetrics.actionHorizontalInset | 20 | Horizontal action inset |
| ControlMetrics.actionVerticalInset | 12 | Vertical action inset |
| Radius.small | 4 | Small artwork and nested geometry |
| Radius.chip | 6 | Chips and action controls |
| Radius.row | 6 | Rows |
| Radius.card | 8 | Bounded surfaces |
| Radius.hero | 4 | Food photography |
| Radius.sheet | 18 | Sheet corners |

Minimum heights are floors. Labels grow. Keep hit shapes aligned with the drawn
control, and constrain photo hit testing to the crop. Do not blindly replace
artwork geometry, progress tracks or native controls with these dimensions.

## Shared components

| Component | Contract |
| --- | --- |
| PrimaryActionButton | Orange rectangular commit, dark label, disabled and busy states, accessible progress, multiline AX label |
| SecondaryActionButton | Paper surface with olive outline/label; same height and text-growth contract |
| DesignChip / SelectChip | Small-radius selection controls; spoken selected state and a noncolor visual cue where needed |
| IconDiscButton / DesignIconButton | Accessible 44-point action; legacy names do not prescribe round chrome |
| OptionRow | Flat peer choice, title/detail, bottom rule, combined spoken label |
| RecipeArtwork | Near-square corners, stable geometry, bounded hits, quiet missing-photo state |
| PlatedMasthead | Serif wordmark, Add and utilities, regular serif page title below |
| EditorialAddButton | Header Add opens the shell's existing create flow; it never changes tabs |
| PlateTabBar | Plain four-destination bottom bar, SF Symbols, olive selection, no center Add or illustrated icons |
| plFloatingGlass | Legacy API name; renders opaque canvas and a rule in Editorial |
| plTileShadow / plDishShadow / plCardShadow / plFloatShadow | Legacy layout-compatible modifiers, now flat |

Existing API names retained for compatibility are not invitations to restore the
retired material or shape. New components should be named for role.

## Screen behavior

Plan keeps its date wheel and Week/Month controls visible above the selected
dinner. The wheel is available immediately whenever Week is selected.
Recipes uses a photo grid, visible search and one filter sheet. Groceries keeps
its real date range, pantry choice and meal provenance. Table preserves the
invite-only audience and post semantics. Profile, household, activity, editors,
sheets, cooking and settings share the same tokens and fonts.

The static deep green launch lockup exits when the app is ready; it imposes no
animation delay. Sign-in uses a photographic welcome. Setup and tour backgrounds
use the selected canvas. Widgets register the same fonts and copy the checked palette;
widget snapshot data and deep links retain their existing contracts.

## States, accessibility and evidence

Prefer native semantics and stable identity. Use brief scoped motion; honor
Reduce Motion for geometry and custom effects. Surfaces are opaque by default.
Use a stronger rule for increased contrast, and never communicate state through
color alone. Disabled does not mean illegible. Busy blocks repeated activation.
Accessible text reflows; compact chrome keeps full spoken names and large-content
viewing where appropriate. No gesture is the only way to complete a task.

`DesignComponents.swift` includes local Light, Dark, AX5 and host-accessibility
preview definitions. Preview definitions are not proof they have been rendered.
Read-only accessibility flags must be configured in the host settings.

Change the owning token/component before adding a page override. Update this
reference and `DESIGN.md` with it. Run design/token checks, build, test, then inspect
screens and interactions. Keep release evidence in the dated implementation
report. Do not claim complete VoiceOver, iPad or device validation without it.


## Shared selection and wheel behavior

`EditorialSegments` owns the cream moving selection, continuous capsule rail,
selected semantics and reduced-motion equivalent for Week/Month, Grocery scope,
and Table audience. Table's capsule refinement from the parallel screen-review
chat is retained. Shared chips, date selectors, settings and award filters use
the same selection roles; structured appearance cards use a cream border and
checkmark rather than inverting their preview content. Supporting panels are
closer to the deep canvas. Orange remains the primary action role.

The date wheel uses native velocity and snap behavior, a centered initial anchor,
local preview while moving, and one plan commit at rest. Native selection feedback
is quantized by crossed day and coalesced during fast flings. Programmatic movement
is silent and interruptible. The interaction value is tested separately from its
rendering. Day adjustments, week actions, Today, direct calendar navigation and
keyboard arrows supplement touch. Reduce Motion removes programmatic translation.
