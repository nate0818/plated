# Plated

A meal scheduling app for a household — plan the week, cook from your own
recipes, shop from a list that builds itself, and see what you actually eat.

Native iOS and iPadOS, SwiftUI, SwiftData over CloudKit. Everything stays in
your iCloud account, apart from a small directory that answers which of your
contacts are already on Plated (see `docs/privacy-policy.md`).

A household is shared across Apple IDs through a second CloudKit share: every
member sees and edits one plan, one grocery list and one cookbook, and a Table
guest sees none of them. `docs/household.md` is the contract that sync, the
invitation links and the join flow are written to; read it before touching any
of them.

---

## Status

**1.0 release candidate.** The four core rooms (Plan, Recipes, Groceries and
Table), household sharing, onboarding, widgets, App Intents, Cook Mode and the
Plated directory are implemented. Automated unit, design-token, static-analysis
and unsigned Release archive gates run cleanly on the candidate.

Distribution is deliberately still blocked on the external evidence listed in
[`docs/app-store-quality-audit.md`](docs/app-store-quality-audit.md): deploy the
newest additive CloudKit field and the directory-deletion backend to Production,
complete automatic Sign in with Apple token revocation, run the two-account and
physical-device matrix, complete App Store privacy disclosures, and prove a
signed archive/export. The editable App Store draft is now aligned to 1.0.0,
free, U.S.-only, and populated with version copy; it remains deliberately
unsubmitted with no build selected. Its five iPhone and five iPad screenshots
are uploaded and checksum-verified. Do not turn release gates into documentation
checkmarks without the corresponding device or console evidence.

Table safety reports are handled under the privacy-preserving operational
procedure in [`docs/table-moderation-runbook.md`](docs/table-moderation-runbook.md).
The exact App Store privacy-label answers and their release guards are mapped in
[`docs/app-store-privacy-disclosures.md`](docs/app-store-privacy-disclosures.md).

## What it does

**Plan the week.** Seven days, four slots each (breakfast, lunch, dinner,
snack). Drop a recipe into a slot, or type a freeform entry for takeout and
leftovers. Check a meal off when you actually cook it — that checkmark is what
feeds every number in Insights.

**Keep the recipes you use.** Ingredients with quantities, units, and store
aisles; instructions; timing; tags. Mark pantry staples so olive oil stops
showing up on every shopping list.

**Shop without building a list.** The grocery list rolls up the week's planned
meals, scaling quantities to the servings you scheduled and merging duplicate
ingredients. One tap sends it to Apple Reminders, so it is on your watch and in
your partner's hands at the store. Hand-added items and checkmarks survive a
rebuild.

**Cook for the people you actually have.** Household profiles carry dietary
notes and a list of ingredients to flag. Any recipe containing one gets a
warning inline on the plan, and is skipped entirely by suggestions.

**Plan the big ones.** A gathering groups several meals under one heading —
Thanksgiving, a birthday, friends coming over — tracks a guest count, and
mirrors into your calendar with the menu written into the event notes.

**See what you eat.** How many times you have made each dish, over 30 days or a
year. Variety, home-cooked share, breakdown by meal. Plus an "out of rotation"
list of recipes you have forgotten about.

**Get a nudge when the weather cooperates.** WeatherKit pulls tomorrow's
forecast, buckets it into a mood (cold, rainy, grill weather), and matches it
against dishes tagged for that mood:

> It's going to be 55° and mostly cloudy — great day for your chili, Nate.

WeatherKit supplies the forecast; the recipe ranking itself is local and
instant: weather match, how long since you last made it, favorite status, and
whether it fits a weeknight. No generative model is involved.

## Requirements

- Xcode 26 or later
- iOS / iPadOS 18.0 or later
- An Apple Developer account for CloudKit and WeatherKit (see below)

## Getting started

```bash
open Plated.xcodeproj
```

Pick a simulator and run. A fresh simulator starts empty, the same as a phone:
no household, so every widget and half the screens have nothing to show. To
put the preview household into the live store, launch with the Debug-only
`-plated-seed-sample` argument (`xcrun simctl launch <udid>
com.natemeadows.plated -plated-seed-sample`). Never do that on a phone signed
into iCloud, because the sample rows would reach the owner's CloudKit database.

### Running on a real device

Merging to `main` does not touch the phone. Installing is a manual step, so a
device silently stays at whatever commit was last built to it — which reads,
convincingly, as "the new work isn't live." One command closes that gap:

```bash
make phone
```

It builds the working tree, installs it on the paired iPhone, and relaunches
the app, printing the commit it just shipped. It finds the device itself (set
`PLATED_DEVICE` to a UDID to override) and warns when `main` is ahead of the
tree you are shipping or when the tree is dirty.

| Command | What it does |
| --- | --- |
| `make phone` | Build, install, launch |
| `make phone-install` | Install without launching |
| `make phone-purge` | Launch with `-plated-purge-cloud`, wiping the CloudKit zone and local store (Debug only) |

Anything after `--` is passed to the app as a launch argument, so
`scripts/phone -- -plated-tab table` opens straight to the Table. The phone
must be unlocked, and either on the cable or on the same network.

### Capabilities and signing

The full capability set is wired: `config/PlatedApp.entitlements` carries
Sign in with Apple, iCloud (CloudKit, container `iCloud.com.natemeadows.plated`),
WeatherKit, push (`aps-environment`), and the app group; both targets sign
under team `JA9M6TYXYL` with automatic signing, and the app target sets the
`PLATED_CLOUDKIT` compile flag that arms the CloudKit account and sharing
paths. The store is built with
`cloudKitDatabase: .automatic`, so sync is live wherever the entitlement is
honored.

Two things still happen outside this repo: the first device build must run
from Xcode while signed into the developer account, so automatic signing can
register the App ID, app group, iCloud container, and capabilities in the
portal; and WeatherKit can take up to ~30 minutes after that registration
before forecast requests stop erroring. Simulator builds don't enforce
entitlements, so everything compiles and runs there regardless.

### Widgets, Siri, and the shared container

The `PlatedWidgetsExtension` target ships home- and lock-screen views for
Tonight, Table, Cookbook, Groceries and cook turns, plus the Cook Timer Live
Activity. The app writes a snapshot and its current images into the
`group.com.natemeadows.plated` app group whenever the scene changes; widgets
read them from the other side. Both targets carry the app-group entitlement
(`config/PlatedApp.entitlements`, `config/PlatedWidgets.entitlements`); the
group registers under the team on the first Xcode device build.

Siri and Shortcuts get two App Intents with zero setup: "What's for dinner in
Plated" answers with tonight's plan, and "Plate a Dish Tonight" drops a
cookbook dish onto an open tonight. Widgets follow the system light/dark
appearance (the home screen is the system's room, not the app's).

Tables and households use explicit CloudKit record zones and `CKShare`
invitations. Pending mutations have durable outboxes, ownership is keyed by
CloudKit identity rather than display name where available, and the UI reports
whether iCloud is signed out, restricted or temporarily unreachable. The local
fallback remains intentional for an unentitled development build.

### Turning on weather suggestions

WeatherKit needs a paid developer account:

1. Add the **WeatherKit** capability to the target
2. Enable WeatherKit for your App ID in the developer portal

Without it, `ForecastProvider` returns no forecast and the suggestion banner
hides itself rather than showing an error you cannot act on.

### Permissions

Reminders and Calendar access are requested the first time you export a grocery
list or sync a gathering. Location is requested only for weather. Usage strings
live in the target's build settings as `INFOPLIST_KEY_NS*` entries.

## Project layout

```
Plated/
├── PlatedApp.swift          App entry and lifecycle integration
├── Models/                  SwiftData recipes, plans, people, groceries, Table
├── Services/                CloudKit sharing, outboxes, imports, reminders
├── Support/                 Store, design system, routing and regression checks
├── Intents/                 Siri and Shortcuts actions
└── Views/                   Root shell and all feature surfaces

config/
├── PlatedApp.entitlements      App target — full set, see "Capabilities and signing"
├── PlatedWidgets.entitlements  Widget extension — app group only
├── cloudkit-schema.txt         Fields verified as deployed to Production
└── ExportOptions.plist         App Store distribution export

PlatedWidgets/                  Home-screen widgets and Cook Live Activity
PlatedTests/                    Unit and contract regression coverage
supabase/                       Directory schema and Edge Functions
web/                            plated.food, privacy policy and founder console
```

### Notes on the data model

Every model is written to CloudKit's constraints: no unique attributes, all
relationships optional, every stored property carries a default. Breaking any
of those makes the container fail to initialize at launch rather than at build
time, so keep to the pattern when adding models.

Grocery merging combines lines with the same ingredient name *and* the same
unit. Different units stay separate rather than guessing at conversions — "2
cups rice" and "1 lb rice" are genuinely different asks.

## Product state

Implemented for 1.0:

- Week and month planning, drag/move alternatives and cooked-state history
- Recipe creation, photos, URL/paste/scan imports and cookbook sharing
- Rolling grocery aggregation, meal scoping, provenance and Reminders export
- Household roles, CloudKit invitation/leave/remove flows and shared plan data
- Private Table posts, comments, polls, reactions, activity and durable retries
- Cook Mode with timers, Live Activity, resume and notification deep links
- Home-screen widgets, Siri/Shortcuts, Calendar and local WeatherKit suggestions

Intentionally outside 1.0: public discovery, payments, a Watch app, nutrition
and HealthKit. A share-extension source exists, but no share-extension target is
embedded in the shipping archive; in-app URL, paste, scan and photo import are
the supported intake paths for this release.

## License

Private project. All rights reserved.
