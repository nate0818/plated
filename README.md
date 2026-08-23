# Plated

A meal scheduling app for a household — plan the week, cook from your own
recipes, shop from a list that builds itself, and see what you actually eat.

Native iOS and iPadOS, SwiftUI, SwiftData over CloudKit. Everything stays in
your iCloud account; there is no Plated server.

---

## Status

**v0.1 — scaffold.** The data model, services, and screens are in place and the
app runs with seeded sample content. Nothing is App Store ready yet. See
[Roadmap](#roadmap) for what is real and what is stubbed.

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

The ranking is local and instant: weather match, how long since you last made
it, favorite status, and whether it fits a weeknight. No network call, no model.

## Requirements

- Xcode 26 or later
- iOS / iPadOS 18.0 or later
- An Apple Developer account for CloudKit and WeatherKit (see below)

## Getting started

```bash
open Plated.xcodeproj
```

Pick a simulator and run. On a simulator the app seeds a few recipes and some
cooking history on first launch so there is something to look at; a real device
deliberately starts empty, so no sample rows ever reach the owner's CloudKit
database.

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
`PLATED_CLOUDKIT` compile flag that arms `TableSync` (account checks, and
eventually CKShare Tables). The store is built with
`cloudKitDatabase: .automatic`, so sync is live wherever the entitlement is
honored.

Two things still happen outside this repo: the first device build must run
from Xcode while signed into the developer account, so automatic signing can
register the App ID, app group, iCloud container, and capabilities in the
portal; and WeatherKit can take up to ~30 minutes after that registration
before forecast requests stop erroring. Simulator builds don't enforce
entitlements, so everything compiles and runs there regardless.

### Widgets, Siri, and the shared container

The `PlatedWidgetsExtension` target ships two home-screen widgets — **Tonight**
(small: what's on the plate) and **Your Week** (medium: the seven nights and
who cooks). The app writes a snapshot (`week-snapshot.json` + `tonight.jpg`)
into the `group.com.natemeadows.plated` app group whenever the scene changes;
the widget reads it from the other side. Both targets carry the app-group
entitlement (`config/PlatedApp.entitlements`, `config/PlatedWidgets.entitlements`);
the group registers under the team on the first Xcode device build.

Siri and Shortcuts get two App Intents with zero setup: "What's for dinner in
Plated" answers with tonight's plan, and "Plate a Dish Tonight" drops a
cookbook dish onto an open tonight. Widgets follow the system light/dark
appearance (the home screen is the system's room, not the app's).

`Services/TableSync.swift` is the Phase 3 scaffolding for real multi-household
Tables over CloudKit sharing (CKShare per Table). It reports capability
honestly — without the iCloud entitlement it composes the invite message the
host sends by hand from onboarding's "Send the invite".

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
├── PlatedApp.swift          App entry, ModelContainer, CloudKit configuration
├── Models/                  SwiftData models
│   ├── Recipe.swift
│   ├── Ingredient.swift     + GroceryAisle
│   ├── PlannedMeal.swift    One dish, one slot, one day
│   ├── HouseholdMember.swift
│   ├── Gathering.swift
│   ├── GroceryItem.swift
│   ├── MealSlot.swift
│   └── WeatherMood.swift
├── Services/                Logic that does not belong in a view
│   ├── GroceryListBuilder.swift   Meal plan → consolidated shopping list
│   ├── RemindersExporter.swift    EventKit → Apple Reminders
│   ├── CalendarSync.swift         Gatherings → system calendar
│   ├── ForecastProvider.swift     WeatherKit + CoreLocation
│   ├── SuggestionEngine.swift     Weather- and history-aware ranking
│   └── MealInsights.swift         Cooking analytics
├── Views/
│   ├── ContentView.swift          Tab shell (sidebar-adaptable on iPad)
│   ├── WeekPlanView.swift
│   ├── RecipeLibraryView.swift    + Detail, Editor, Picker
│   ├── GroceryListView.swift
│   ├── GatheringsView.swift
│   ├── HouseholdView.swift
│   └── InsightsView.swift
└── Support/
    ├── Calendar+Week.swift
    ├── Color+Hex.swift
    └── SampleData.swift

config/
├── PlatedApp.entitlements      App target — full set, see "Capabilities and signing"
├── PlatedWidgets.entitlements  Widget extension — app group only
└── Plated.entitlements         Historical reference; superseded by PlatedApp.entitlements
```

### Notes on the data model

Every model is written to CloudKit's constraints: no unique attributes, all
relationships optional, every stored property carries a default. Breaking any
of those makes the container fail to initialize at launch rather than at build
time, so keep to the pattern when adding models.

Grocery merging combines lines with the same ingredient name *and* the same
unit. Different units stay separate rather than guessing at conversions — "2
cups rice" and "1 lb rice" are genuinely different asks.

## Roadmap

**Working now**
- Week calendar with four slots per day and cooked-state tracking
- Recipe library with ingredients, aisles, pantry staples, moods, tags
- Grocery aggregation with servings scaling and non-destructive rebuild
- Reminders export and Calendar sync via EventKit
- Household profiles with dietary conflict warnings
- Insights: frequency, variety, home-cooked share, out-of-rotation
- Local weather-aware suggestions

**Next**
- Drag-and-drop between slots on the week plan
- Recipe photos and import from a URL
- Assigning planned meals to a gathering from the plan screen
- Per-member attendance on a meal, so servings scale to who is home
- CloudKit share sheet for the household record zone
- Widget: what's for dinner tonight
- App Intents so Siri can answer "what's for dinner"

**Later**
- Foundation Models pass over suggestion phrasing and recipe parsing
- Leftover tracking that schedules the second night automatically
- Store-specific aisle ordering
- Watch app for the grocery list
- Nutrition and HealthKit

## License

Private project. All rights reserved.
