# Plated: Editorial

Approved direction: Editorial, October 16, 2026. The default appearance is the deep green Editorial room (`#191C17`), with
cream serif titles and sage supporting accents. Light is an optional setting,
not the initial design presentation. Primary CTAs retain the original
Plated orange at the user's request. This replaces the previous rounded,
Gabarito/Jakarta, floating-tray system.

## The experience

Plated helps a household capture a recipe, plan a night, shop, cook, then
remember or intentionally share the meal. Food, people and useful context lead.
The interface feels like a well-set recipe journal: deep green, fine rules, generous
photography, serif titles and simple controls.

Four stable destinations remain **Plan, Recipes, Groceries and Table**. Profile
opens from the consistent account control. Household is a pushed shared workspace;
Settings is a pushed personal control center. Back pops within a destination.
A root reselect returns to that destination's root. Add is a header action,
not a tab. Tasks use sheets and preserve valuable drafts. Cooking uses a focused
full-screen session with explicit Minimize and End actions.

## First arrival

The app icon uses the custom cream P with its open, curved bowl on deep green.
Default and Dark share the same artwork; Tinted uses the monochrome version.
The system owns the corner mask. No gradient wordmark or trailing dot.

Launch is a readiness-driven canvas, with no timed logo interstitial. Welcome
uses a believable weeknight photograph, the editorial wordmark, and a short
product promise. Apple sign-in and local use remain available. New users enter
the real Recipes empty state, with Add your first recipe, Plan a night, and an
invitation route. Incoming invitations retain their destination through welcome.
Profile photos, contacts and the feature tour are not mandatory setup. Ask for a
missing name when joining a household. Saving opens the actual recipe detail;
there is no celebration interstitial, and failed saves retain the draft.

## Source of truth

- `Plated/Support/Theme.swift`: semantic colors, shape, spacing, control metrics,
  materials and shared controls.
- `Plated/Support/BrandFonts.swift`: bundled Newsreader and DM Sans, scaled type
  and optical matching.
- `Plated/Views/Components/DesignComponents.swift`: artwork, mastheads, chips,
  header Add, icon actions and the local preview gallery.
- [Design-system reference](design/design-system.md): component roles, tokens
  and verification requirements.
- Widget palette and font registration live in `PlatedWidgets.swift`; `make tokens`
  must pass. Old HTML explorations and historical review screenshots are not
  instructions for the current design.

## Editorial foundations

**Typography.** Newsreader Roman sets page, section and recipe titles with
regular or medium strokes. DM Sans sets body, metadata, controls and navigation.
Use `.plType`, `.editorial` and `.sans`. Hierarchy comes from size, space and
position before weight. Text scales with Dynamic Type. Reflow and scroll before
shrinking meaningful content. Fixed artwork and bounded chrome are exceptions,
not a way to cap an entire page.

**Color.** The default `canvas` is deep green and `ink` is cream. The optional
Light appearance uses paper and green-black ink. Readable supporting text is
`inkSecondary`. `inkFaint` is decoration only. Selected date and choice controls
use `selectionFill` (`ink`) with `onSelection` (`canvas`) text: cream with dark text in Editorial. Keep panels
close to the canvas with fine borders; avoid broad pale green fills. Olive is
reserved for small supporting accents. Original orange `primaryAction` is for committing CTAs,
with dark `onPrimary` text in both appearances. Never reuse orange as an ambient
background or selection indicator. Errors use `dangerText`, not olive or orange.
Person colors remain identity metadata; stored hex keys are not migration targets.
Photos use `scrim` and `onScrim` where an overlay is needed.

**Shape.** Photos have near-square continuous corners. Buttons and chips use a
small continuous rectangle. People remain circles. Do not reintroduce capsule
CTAs, illustrated tab icons, iridescent selection glows, or the central Add disc.
Segmented controls use a continuous capsule rail and selection; they reflow
vertically at accessibility sizes. Sheets keep native dismissal and a restrained corner radius.

**Surface.** Pages, controls and the bottom navigation use the opaque canvas: deep green
by default, paper only when Light is deliberately chosen. Fine
rules and spacing establish groups. Shadows are removed from the shared
surface styles. Use system presentation materials where a platform component
owns them; do not add custom glass to ordinary content or navigation.

**Layout.** Use 24-point phone gutters, 28-point section spacing and 12–16-point
component spacing. Photos keep their own geometry. Page-level titles are allowed
to wrap. Compact tabs, chips and segments keep concise single-line labels.
Primary/secondary action labels may wrap at accessibility sizes and grow vertically.
Interactive targets are at least 44 by 44 points and have matching hit shapes.
Plan opens with a compact personal greeting, a horizontal date row and the selected day's content. Today is selected on arrival; its Tonight region contains the meal name, bounded artwork, cook/servings and primary action. Below the date row, only that date's meals appear. Vertical scrolling reveals more of the same day, never earlier or upcoming days. The date row stays available while that content scrolls. Calendar remains an explicit secondary mode with a clear Back to tonight action. This supersedes the Coming up agenda at the user’s request on October 17, 2026. Recipes keeps
search visible. Grocery rows preserve meal provenance. Table shows audience
compactly before posts.

An empty dinner uses a compact decision panel with Plan tonight and Eating out
visible together (stacked at larger text sizes). Below the selected day's meals,
show that day's local forecast and a clearly labeled Last 7 days household dinner
log. Cooked means marked complete; Eating out counts marked nights through today,
not future plans. Never substitute sample counts for missing history. Weather
permission, loading and recovery states stay visible, with Apple attribution for
live forecasts. These supporting sections are context, not another dated meal feed.

## Interaction and accessibility

Choose the standard SwiftUI profile: familiar semantics, responsive controls,
short causal feedback. Use native Button, Menu, Toggle and navigation semantics.
Use stable model identity and a single owner for presentation state. Do not
coordinate UI presentation or animation with arbitrary delays.

Honor Reduce Motion locally for geometry, rotation and timelines. Shared motion
removes spring bounce; large arrivals have fade alternatives. Editorial surfaces
are already opaque. Increase Contrast strengthens useful boundaries. Selected
controls expose `.isSelected`; color is never their only state cue. Icon actions
have useful accessible names. Root tabs provide large-content viewing.

A busy primary action keeps its orange paint and spinner, exposes progress and
blocks repeat activation. Disabled controls keep readable labels and an explicit
disabled appearance. Never fade text and its background until they blend together.
Meaningful progress, failure and recovery must be available to VoiceOver.

## Product trust and state completeness

Household is the private co-editing workspace for Plan, Recipes and Groceries.
Table is the explicit invite-only publishing audience. Saving, cooking or checking
an item never posts on someone's behalf. Before posting, show the destination and
who can see it. People is the authority for membership. Preserve authorship,
audience, time, source and pending/delivery state. Own-post and other-post menus
have different permissions. Published deletion means deletion for the audience,
not just removing a local row. Reporting and reversible blocking stay available.

Invited means sent, accepted means accepted. Opening a composer proves neither.
Show organizer roles, live sync truth and pending local edits honestly. Joining,
leaving and removal name what becomes shared, what is retained, and what is lost.
Never infer authorization from a display name. No public discovery is implied.

Every networked surface distinguishes initial/loading, ready, empty, failed,
offline/stale and pending states. Retry preserves work and avoids duplicates.
An empty state must know why it is empty. Do not show a false success or absence.
Counts appear when useful and true. No fabricated urgency, streak punishment or
social ranking. Awards are keepsakes; unfinished progress is private.

Cooking preserves its frozen recipe, yield, step, note draft and timer across
Minimize. End asks once and clears the session, leaving the planned meal intact.
Recipe edits must not mutate the active cooking instructions.

## Copy

Titles are nouns, buttons name outcomes, captions state facts. Use Plan a night,
Add a recipe, Add to Groceries, Start/Resume cooking, Mark cooked, Post to Table,
and Assign a cook. Household, Table, Profile and Settings are distinct concepts.
Use Organizer for the household role. No em dashes in user-facing copy; do not
apply this rule to imported recipe separators. Avoid metaphor in functional chrome.

## Verification

Run `make design tokens`, build Plated and its widgets, and run the existing tests.
Inspect real screenshots, not just mockups. Verify smallest/typical/iPad windows,
light/dark, AX5, long and missing content, VoiceOver, keyboard access, increased
contrast, reduced effects, repeated taps, interrupted navigation and backgrounding.
Photos must not intercept hits outside their visible crop. Gesture actions need
accessible alternatives. Device-only integrations require physical-device evidence.
Record what was tested and what remains unverified. A green build or suite alone
is not approval of every layout or interaction.


## Date wheel contract

Use native scroll physics and aligned targets. The centered day previews locally
while scrubbing; commit the dinner plan once scrolling rests. Selection feedback
occurs at crossed dates and deliberate date taps, never on initial layout or a
programmatic reset. Coalesce ticks during fast flings. Today and direct date
navigation interrupt previous motion; stale deceleration cannot change that date.
Use the native centered anchor on iOS 26 and a bounded native fallback on iOS 18.
Reduce Motion removes programmatic travel. Selected dates expose an adjustable
VoiceOver action; named day/week/Today actions and arrow keys remain available.
Physical Taptic Engine feel requires an iPhone check.

`make tokens` checks both widget parity and 31 website palette roles in both
appearances. All website routes use Editorial by default, including authentication
and error pages. Public screenshots must come from the current native build.
