# Release verification · 17 October 2026

**Beta distribution:** the user subsequently authorized TestFlight distribution to all testers with these gaps disclosed. See [build 34](../../testflight-34.md).

**Release decision: not yet cleared.** A second device/account is unavailable, so live multi-account CloudKit verification cannot be completed. This record separates runtime evidence from source tests; passing local merges does not establish cross-account delivery.

**Later Plan refinement:** the user requested only the selected day's content below the date row. See [selected-day implementation and checks](SELECTED_DAY.md). It supersedes the earlier Coming up layout, and adds physical date-selection and VoiceOver verification.

**Checks continued with the phone disconnected:** see [additional fixes and simulator evidence](PHONE_DISCONNECTED.md), including Calendar cleanup, date-boundary widget tests, keyboard dismissal and VoiceOver form journeys. These latest repairs are not yet installed on the phone.

## Defects found and repaired during release checks

- Calendar permission errors were present in the accessibility tree but below the visible form. Feedback now stays directly above Save changes; denial, retry, and saving locally were exercised again.
- Widgets relied only on a provider refresh request at midnight. The production provider now supplies an explicit midnight entry that expires dinner, grocery counts and meal photos, retaining durable Table/Cookbook cards. Unknown/stale cook turns no longer say “Nobody yet.”
- Grocery widgets could claim “Nothing to buy” until Groceries was opened. Snapshot publication now uses the production grocery builder in a separate ModelContext, reading saved meals without committing unrelated edit drafts. Purchase quantities, pantry preference and persistent manual extras are regression-tested.
- The large Tonight widget cut off the sixth upcoming night on iPhone SE. A shorter split header and compact rows expose all six nights.
- Grocery widget system margins stacked with custom margins, squeezing content. The view now owns its insets; compact status copy wraps. The large list leaves room for its remainder count. Medium remainder counts now subtract the four visible rows, and the completed state explains that everything was bought.
- VoiceOver spoke the decorative initial beside “You're cooking” on Tonight. That avatar is now hidden from accessibility; the adjacent cook text provides its meaning.
- Physical VoiceOver exposed a second Tonight issue: image recognition could announce photo objects in place of the meal name. Local and shared dinner cards now have explicit meal labels and button traits.

## Evidence

| Check | Result and limits |
|---|---|
| Native regression suite | `native-final.xcresult`: 419 executed, **418 passed, 1 intentionally skipped, 0 failed**. The skip is the opt-in EventKit test, run separately. Includes the three new WidgetBridge regressions and local household/Table queue, merge, authorization and invitation contracts. |
| Actual EventKit create/update/recreate/delete | `eventkit-retest.xcresult`: **1 passed** on the isolated iOS 26.5 simulator. Production CalendarSync creates an event with title/time/location/menu/guest count, updates without duplication, recreates after external deletion, and removes idempotently. UUID-marked test events are removed. |
| Physical EventKit round trip | `calendar-device.xcresult`: **1 passed** on iPhone 18 Pro/iOS 27.2, after the user granted Full Access. The same production create/update/recreate/remove checks passed against the phone's default calendar. Temporary UUID-marked events were removed. Other calendar/account configurations remain untested. |
| Calendar authorization grant | `calendar-and-widget-timeline.xcresult`: grant through the real OS prompt closes the form successfully; the other four tests exercise widget production source. |
| Final denied Calendar flow | `widget-calendar-final.xcresult`: denied access → visible error → retry → local-only save passed. Screenshot visually checked. |
| Widget production timeline | Four tests in `widget-calendar-final.xcresult`: midnight expiry without a provider refresh, missing snapshot, week-old snapshot, and opaque item IDs in links. These are deterministic provider tests, not an observed overnight WidgetKit scheduling run. |
| System widget gallery | All **13 Home Screen family variants** traversed through SpringBoard on iPhone SE/iOS 26.5. Final screenshots under `verified-screens/`; populated Grocery shows 17 items before opening Groceries, and large Tonight shows all six upcoming dates. |
| Physical widget gallery | `device-traits-gallery.xcresult`: all **13 Home Screen variants** traversed on iPhone 18 Pro/iOS 27.2. Large Tonight/Grocery and medium Whose Turn screenshots visually checked. These read the phone's existing widget snapshot; preview data is not published to its app group. |
| Lock Screen circular/rectangular gallery | `widget-lock-six.xcresult`: six variants traversed on iPhone 17 Pro/iOS 27.0 Simulator. All three pair screenshots in `verified-screens/` visually checked: Tonight's title/cook, Grocery's count, and Whose Turn's name/time fit. The ingredient sample intentionally truncates to one line. |
| Lock Screen inline gallery | `widget-lock-and-routes-final.xcresult`: the Lock Screen test **passed**, traversing all six circular/rectangular previews and asserting all three inline variants. `verified-screens/lock-screen-inline-three.png` was visually reviewed: Salmon Night, 17 to buy and You cook tonight fit. The bundle also contains a failed routing setup check, so it is not an overall passing bundle. |
| Empty grocery widgets | `widget-empty-captures.xcresult`: all three sizes captured and visually checked. “Nothing to buy” and its explanatory copy fit. The gallery's hosted text is absent from its accessibility tree in this state, so page assertions alone are not treated as visual evidence. |
| Installed widget deep link | Cookbook installed through the system gallery, then tapped. The displayed Pancake Dinner recipe opens, rather than only the cookbook root. Passed in `widget-calendar-final.xcresult`. |
| Table and Grocery installed widget links | `widget-routes-final.xcresult`: **1 passed**, installing each widget on iPhone 17 Pro/iOS 27.0 Simulator, tapping into the expected post thread or populated shopping list, and removing each temporary widget. Stable preview-only post IDs exercise item routing without CloudKit writes. Earlier attempts failed in harness setup/queries; the final run passed both destinations and cleanup. Both destination screenshots in `verified-screens/` were visually reviewed. |
| Physical Tonight widget tap | In `device-widget-tap.xcresult`, installation and tap-through to Plan passed their assertions; the test failed during cleanup, so the bundle is not a passing test. The separate `device-widget-cleanup-reachable.xcresult` passed and confirmed the temporary widget was removed. Initial cleanup attempts encountered a different system removal control and an overlapping notification banner. |
| VoiceOver simulator | `voiceover-corrected.xcresult`: **1 passed**, traversing seven fixture screens through the actual iOS 27 XCUIVoiceOverService. `voiceover-simulator-transcript.txt` records spoken order. Initial harness failures remain diagnostic evidence. |
| VoiceOver physical device | `voiceover-device.xcresult`: **1 passed**, seven-screen spoken focus traversal on iPhone 18 Pro/iOS 27.2. `voiceover-device-transcript.txt` omits unrelated notification content. Notifications interrupted some announcements; traversal resumed and reached the target controls. This pass does not by itself verify gestures. |
| Physical VoiceOver activation | `voiceover-device-gesture.xcresult`: **1 passed**. VoiceOver focused Start cooking; the user physically double-tapped the iPhone and confirmed “Cooking opened.” The test independently detected the cooking screen. |
| Physical dinner label retest | `device-traits-gallery.xcresult`: the other passing test confirms “Salmon Night Button,” the cook/serving controls, and Start cooking are spoken in sequence. See `voiceover-device-dinner-transcript.txt`. |
| Device build | Signed current app/extension build succeeded and installed on Nate’s iPhone 18 Pro/iOS 27.2. Development registration/profile updates explicitly authorized by the user. App launches into the in-memory review fixture. |
| Design rules | `make design`: **163 Swift files passed**. App/extension/test-host Simulator builds passed. |

`widget-calendar-final.xcresult` contains six passing tests total (Calendar denial, gallery/install/deep link, four provider tests).

The earlier `voiceover-native-input.xcresult` was host-assisted accessibility activation in Simulator. It does **not** establish a physical VoiceOver double-tap. The harness now gates that manual probe behind `PLATED_MANUAL_VOICEOVER_PROBE=1` and waits for a human gesture.

## Outstanding release gates

- Physical VoiceOver rotor use and complete form journeys on the latest build. Seven-screen physical speech traversal and Start cooking double-tap passed earlier; additional simulator form journeys and native accessibility actions are documented in the disconnected-phone pass.
- Physical Lock Screen variants and actual scheduling across midnight. All nine Lock Screen previews passed in Simulator. Installed Tonight tap-through passed on the phone; Cookbook, Table and Grocery tap-throughs passed in Simulator. The latter three still need physical-device coverage.
- Additional Calendar providers/account configurations. The default-calendar round trip and authorization passed on the physical phone; moving an event between two temporary local calendars and editing it passed in Simulator.
- Two different iCloud accounts: household join, Table invite, remote plan/cook/serving edits, grocery check-off/removal/restore, publication, concurrent changes, offline queues, reconnect and revocation. The user confirmed no second test device/account is available.

The concrete [two-account verification checklist](MULTI_ACCOUNT.md) records the remaining live journeys and pass criteria.

## Device cleanup

The temporary Tonight widget and the temporary `UIAudit.xctrunner` app are removed. iOS rearranged the existing Weather and Fitness widgets while adding/removing it. The user explicitly chose to arrange those widgets himself, so no further Home Screen changes were made. The unused restoration test was removed. The recovery removal test remains opt-in so a later full harness run cannot delete a personal widget automatically. The in-memory review process was closed and verified stopped, leaving the next ordinary launch to open the regular model store.

## Safety and reproducibility

Simulator devices are dedicated audit fixtures: iPhone SE `BD07412B-A618-4313-A5F1-005DBB7A09CF` (26.5) and iPhone 17 Pro `6F47F1FD-52AE-4C35-8D2F-BFE1A52A332F` (27.0). Device app UI tests use `-plated-design-review` (memory-only). No `-plated-seed-sample`, purge, real invitation, household post or release upload was used. Widget preview publication is DEBUG + Simulator-only.

The throwaway harness compiles the actual widget sources with `PLATED_WIDGET_TESTS`, excluding only their `@main` entry point. It does not copy the timeline implementation into tests. For updated unsigned Simulator runners, uninstall only `com.natemeadows.plated.UIAudit.xctrunner` before running: otherwise this environment reused a stale runner binary.

Local `.xcresult` bundles/raw exports are ignored. Curated PNGs/text are retained beside this record. Earlier failed attempts remain as diagnostic evidence; they are not release passes.
