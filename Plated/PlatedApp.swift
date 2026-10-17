import SwiftUI
import SwiftData
import UIKit

/// The selected Editorial room is deep green, independent of the phone's theme.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let editorial: Appearance = .dark
    static let migrationKey = "didAdoptEditorialAppearance20261016"

    static func applyEditorialDefault(to defaults: UserDefaults) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        let saved = defaults.string(forKey: "appearance").flatMap(Appearance.init(rawValue:))
        // Older automatic defaults must not turn the selected green design into cream.
        // A deliberate Light choice remains available, including after this migration.
        if saved == nil || saved == .system {
            defaults.set(editorial.rawValue, forKey: "appearance")
        }
        defaults.set(true, forKey: migrationKey)
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Editorial"
        }
    }

    /// Following the phone is an optional setting; Editorial stays deep green.
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var uiStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct PlatedApp: App {
    @AppStorage("appearance") private var appearanceRaw = Appearance.editorial.rawValue

    private var appearance: Appearance {
        Appearance(rawValue: appearanceRaw) ?? .editorial
    }
    @Environment(\.scenePhase) private var scenePhase
    /// Only for `userDidAcceptCloudKitShareWith`, which has no SwiftUI
    /// equivalent — see ShareAcceptor.
    @UIApplicationDelegateAdaptor(ShareAcceptor.self) private var shareAcceptor

    /// Flags that run the app over the memory-only preview container rather
    /// than the live store. The household observer must not be installed
    /// on those launches: `HouseholdSync.ensureObserving` reaches for
    /// `PlatedStore.shared`, which would spin up the real store and its
    /// mirror beside the preview.
    private static let previewFlags = [
        "-plated-design-review",
        "-plated-review-opener",
        "-plated-review-sign-in",
        "-plated-open-edit-profile",
        "-plated-open-recipe-detail",
        "-plated-open-recipe-ingredients",
        "-plated-review-cooking-timer",
        "-plated-review-recipe-share",
        "-plated-review-recipe-picker",
        "-plated-review-gathering",
        "-plated-review-plan-night",
        "-plated-review-move-meal",
        "-plated-review-add-household-member",
        "-plated-review-banner-crop",
        "-plated-review-tour",
        "-plated-review-onboarding",
        "-plated-test-groceries",
        "-plated-test-probe-cleanup",
        "-plated-test-drag-moves"
    ]

    /// One boundary shared by the app, shell, feed and app delegate. A
    /// preview-backed launch may read and mutate its in-memory fixture, but
    /// it must never confirm identity, pull CloudKit, or repair the live
    /// store sitting beside it.
    static var usesPreviewContainer: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return previewFlags.contains(where: { arguments.contains($0) })
        #else
        return false
        #endif
    }

    private static var usesOnboardingReview: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-plated-review-tour")
            || arguments.contains("-plated-review-onboarding")
        #else
        return false
        #endif
    }

    /// See PlatedStore — the app and App Intents share this one container.
    let container: ModelContainer = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if usesPreviewContainer {
            let preview = SampleData.previewContainer
            if arguments.contains("-plated-review-onboarding") {
                // A fresh, memory-only cookbook makes the complete first-use path testable.
                try? preview.mainContext.delete(model: PlannedMeal.self)
                try? preview.mainContext.delete(model: Recipe.self)
                try? preview.mainContext.save()
            }
            if arguments.contains("-plated-design-review") {
                if arguments.contains("-plated-review-removal-unlinked"),
                   let sam = (try? preview.mainContext.fetch(FetchDescriptor<HouseholdMember>()))?.first(where: { $0.name == "Sam" }) {
                    sam.seat = .joined
                    sam.userRecordName = ""
                    sam.participantID = nil
                    try? preview.mainContext.save()
                }
                let fixtureOwner = "ux-audit-tonight"
                if PlanLedger.shared.householdOwner == fixtureOwner {
                    PlanLedger.shared.forget(zoneOwner: fixtureOwner)
                    PlanLedger.shared.householdOwner = nil
                }
                if arguments.contains("-plated-review-empty-tonight") || arguments.contains("-plated-review-shared-tonight") {
                    let meals = (try? preview.mainContext.fetch(FetchDescriptor<PlannedMeal>())) ?? []
                    for meal in meals where Calendar.current.isDateInToday(meal.date) { preview.mainContext.delete(meal) }
                    try? preview.mainContext.save()
                }
                if arguments.contains("-plated-review-dinner-history") {
                    // Memory-only history exercises real counts without touching
                    // the person's dinner log or inventing activity in production.
                    for offset in [-1, -3, -5] {
                        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date.now)!
                        let dinner = PlannedMeal(date: date, customTitle: offset == -3 ? "Eating out" : "Home-cooked dinner")
                        if offset != -3 { dinner.cookedAt = date }
                        preview.mainContext.insert(dinner)
                    }
                    try? preview.mainContext.save()
                }
                if arguments.contains("-plated-review-household-activity"),
                   let sam = (try? preview.mainContext.fetch(FetchDescriptor<HouseholdMember>()))?.first(where: { $0.name == "Sam" }) {
                    sam.name = "Sam Rivera"; sam.seat = .joined; sam.userRecordName = "ux-audit-sam"
                    sam.shareRecordName = "seat-ux-sam"
                    sam.photoData = UIImage(systemName: "person.crop.circle.fill")?.pngData()
                    let meals = (try? preview.mainContext.fetch(FetchDescriptor<PlannedMeal>())) ?? []
                    for meal in meals where meal.isCooked { meal.cook = sam }
                    let oldPosts = (try? preview.mainContext.fetch(FetchDescriptor<TablePost>())) ?? []
                    for post in oldPosts where post.firstName == "Sam" { post.authorID = "ux-audit-different-sam" }
                    let post = TablePost(authorName: "Sam Meadows", dishTitle: "Profile identity dinner", createdAt: .now.addingTimeInterval(-3600))
                    post.authorID = "ux-audit-sam"; preview.mainContext.insert(post)
                    try? preview.mainContext.save()
                }
                if arguments.contains("-plated-review-shared-tonight"),
                   let recipe = (try? preview.mainContext.fetch(FetchDescriptor<Recipe>()))?.first {
                    PlanLedger.shared.householdOwner = fixtureOwner
                    var night = TableShare.RemotePlan()
                    night.recordName = "plan-ux-audit-tonight"; night.shoppingID = "ux-audit-tonight"
                    night.zoneOwner = fixtureOwner; night.authorID = "ux-audit-sam"; night.authorName = "Sam Meadows"
                    night.cookName = "Sam Meadows"; night.cookID = "ux-audit-sam"; night.cookSeat = "joined"
                    night.day = PlanDay.string(.now); night.slot = MealSlot.dinner.rawValue
                    night.title = recipe.title; night.servings = 6; night.hasRecipe = true
                    night.recipeOriginKey = recipe.planningKey
                    if arguments.contains("-plated-review-shared-cook-only") {
                        night.title = "Unplanned"; night.hasRecipe = false; night.recipeOriginKey = ""
                    }
                    var changes = TableShare.Changes(); changes.plans = [night]
                    PlanLedger.shared.absorb(changes, me: "ux-audit-reader")
                }
            }
            if arguments.contains("-plated-design-review") && arguments.contains("-plated-review-drag") {
                PlannerDragChecks.prepareReview(in: preview.mainContext)
            }
            #if targetEnvironment(simulator)
            if arguments.contains("-plated-review-widgets") {
                // Stable fixture IDs let real installed widgets exercise
                // item routing without publishing a post to CloudKit.
                let posts = (try? preview.mainContext.fetch(FetchDescriptor<TablePost>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
                for (index, post) in posts.enumerated() {
                    post.shareRecordName = "ux-widget-post-\(index)"
                }
                try? preview.mainContext.save()
            }
            #endif
            // Explicit UI-test fixture, inside the memory-only preview path.
            if arguments.contains("-plated-design-review") && arguments.contains("-plated-review-notifications") {
                let sampleActivity: [(PlatedNotificationKind, String, String, TimeInterval)] = [
                    (.dishPosted, "Sam Meadows", "Sam shared Pancake Dinner at the Table.", -90),
                    (.commentAdded, "Riley Parker", "Riley replied to your question about Saturday.", -420),
                    (.recipeAdded, "Sam Meadows", "Sam added Pesto Pasta to the cookbook.", -1_800),
                    (.mealPlanned, "", "Dinner is planned for Friday.", -3_600),
                    (.saveReceived, "Riley Parker", "Riley saved your Lemon Butter Salmon recipe.", -7_200),
                    (.voteCast, "Sam Meadows", "Sam voted for Poke Night.", -14_400)
                ]
                for (kind, actor, body, age) in sampleActivity {
                    preview.mainContext.insert(PlatedNotification(
                        kind: kind, actorName: actor, body: body,
                        at: .now.addingTimeInterval(age)
                    ))
                }
            }
            return preview
        }
        #endif
        return PlatedStore.shared
    }()

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-plated-test-drag-moves") {
            do { try PlannerDragChecks.run(); exit(0) }
            catch { print("PLATED DRAG CHECKS FAILED: \(error)"); exit(1) }
        }
        if ProcessInfo.processInfo.arguments.contains("-plated-test-groceries") {
            do { try GroceryRegressionChecks.run(); exit(0) }
            catch { print("PLATED GROCERY CHECKS FAILED: \(error)"); exit(1) }
        }
        #endif
        BrandFonts.registerAll()
        Appearance.applyEditorialDefault(to: .standard)
        #if DEBUG
        // The nine steps are a scale at every content size, or the app has
        // a callout bigger than its display and nobody notices until a
        // screenshot at AX5.
        TypeScale.assertMonotone()
        #endif
        // The household save observer, on the live store's main context and
        // before the first view can save anything. PlatedStore cannot do
        // this itself: its container is a static initialiser with no main
        // actor to hop to.
        if !Self.usesPreviewContainer {
            _ = container
            HouseholdSync.ensureObserving()
        }
    }

    @MainActor
    private static func applyRoomLighting(_ appearance: Appearance) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = appearance.uiStyle
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(appearance.scheme)
                .onChange(of: appearanceRaw) { _, _ in
                    // Belt and braces: preferredColorScheme has been seen to
                    // stick when the flip happens inside an animated binding
                    // or under a presented sheet. The UIKit override is
                    // authoritative and cannot half-apply.
                    Self.applyRoomLighting(appearance)
                }
                .onAppear { Self.applyRoomLighting(appearance) }
                .task {
                    guard !Self.usesPreviewContainer else { return }
                    await SyncStatus.shared.refresh()
                    await TableShare.removeSchemaProbes(from: container.mainContext)
                }
                .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                    // Every planner edit ends in a save, most of them
                    // through autosave with no call site to hook. Three
                    // seconds after the last one, the plan goes out.
                    if !Self.usesPreviewContainer {
                        PlanShare.schedule(reason: "save")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: PlanLedger.nightsDropped)) { _ in
                    // Nights left the ledger with no delivery to rebuild
                    // the reminders through: a leave, a flip, an identity
                    // reset. Without this the 19:00 "Your night tomorrow"
                    // for a table this phone is no longer at fires anyway,
                    // until somebody opens the Plan tab.
                    if !Self.usesPreviewContainer {
                        Task { @MainActor in await NotificationScheduler.rebuild(from: container.mainContext) }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Someone who just switched iCloud back on in Settings
                    // returns here; that is precisely when the warning
                    // should be re-asked rather than left stale.
                    if phase == .active && !Self.usesPreviewContainer {
                        Task {
                            await SyncStatus.shared.refresh()
                            await TableShare.removeSchemaProbes(from: container.mainContext)
                        }
                    }
                }
                .task {
                    // Every preview-backed launch is an inert product demo.
                    // It may exercise local sample UI, but it must not confirm
                    // a real CloudKit identity, clean up, or rewrite the live
                    // app-group ledgers behind that UI. Letting Design Review
                    // do so also races the shell's owner repair: the sample
                    // head can be re-attributed between the shell's fetch and
                    // insert, briefly laying a second "Add your name" owner.
                    guard !Self.usesPreviewContainer else { return }
                    // Rehearsal nights are for one launch. Unless this one
                    // is a rehearsal, the nights a previous one left go,
                    // and the pretend household they pointed at goes too,
                    // or the planner keeps drawing Riley's week forever.
                    if !ProcessInfo.processInfo.arguments.contains("-plated-fake-table-news") {
                        PlanLedger.shared.forget(zoneOwner: PlanLedger.rehearsalOwner)
                        if PlanLedger.shared.householdOwner == PlanLedger.rehearsalOwner {
                            PlanLedger.shared.householdOwner = nil
                        }
                    }
                    // Maintenance: wipe the private CloudKit database, print
                    // a verdict for the console, and quit. PlatedStore ran
                    // local-only this launch, so nothing re-exports. Debug
                    // only — a shipped binary carries no data-nuking flag.
                    // Maintenance: write one row of every model so the
                    // Development schema learns every record type, hold
                    // while the mirror exports them, and quit. Run this
                    // before deploying to Production — CloudKit cannot mint
                    // a type there on demand, so a type never exercised in
                    // Development is a feature that silently fails to sync
                    // for everyone. Debug only; `-plated-purge-cloud` clears
                    // the rows afterwards.
                    #if DEBUG
                    if LaunchFlags.consume("-plated-test-probe-cleanup") {
                        do { try await SchemaProbeRegressionChecks.run(); exit(0) }
                        catch { print("PLATED PROBE CHECKS FAILED: \(error)"); exit(1) }
                    }
                    if LaunchFlags.consume("-plated-prime-share") {
                        print(await TableShare.primeSchema())
                        try? await Task.sleep(for: .seconds(20))
                        exit(0)
                    }
                    #endif
                    #if DEBUG
                    if LaunchFlags.consume("-plated-prime-household") {
                        print(await HouseholdSync.primeSchema(context: container.mainContext))
                        try? await Task.sleep(for: .seconds(5))
                        exit(0)
                    }
                    #endif
                    #if DEBUG
                    if LaunchFlags.consume("-plated-prime-schema") {
                        do {
                            // Primer rows already match nothing on the
                            // wire; the observer would queue every one.
                            HouseholdSync.suppressed = true
                            defer { HouseholdSync.suppressed = false }
                            try SchemaPrimer.prime(into: container.mainContext)
                            print("PLATED PRIME: 12 rows saved — holding while CloudKit exports")
                            try await Task.sleep(for: .seconds(90))
                            print("PLATED PRIME: done — deploy the schema, then purge")
                        } catch {
                            print("PLATED PRIME FAILED: \(error)")
                        }
                        exit(0)
                    }
                    #endif
                    #if DEBUG
                    if LaunchFlags.consume("-plated-unprime-schema") {
                        do {
                            try SchemaPrimer.unprime(from: container.mainContext)
                            try await Task.sleep(for: .seconds(30))
                            print("PLATED UNPRIME: done — deletions exported")
                        } catch {
                            print("PLATED UNPRIME FAILED: \(error)")
                        }
                        exit(0)
                    }
                    #endif
                    // Fixture: the preview household (SampleData) in the live
                    // store, so a widget or a screen can be photographed with
                    // real content on a fresh simulator. Skips itself when
                    // anyone already lives here. Debug only, and never on a
                    // phone signed into iCloud: the mirror would export Sam
                    // and Riley to the real household.
                    #if DEBUG
                    if LaunchFlags.consume("-plated-seed-sample") {
                        HouseholdSync.suppressed = true
                        SampleData.seed(into: container.mainContext)
                        try? container.mainContext.save()
                        HouseholdSync.suppressed = false
                        print("PLATED SEED: sample household in the live store")
                    }
                    #endif
                    // Who this phone is, before anything decides what is
                    // its own (docs/household.md section 5): the head row
                    // takes the identity while the household is unshared,
                    // and rows whose fingerprint drifted while the app was
                    // dead are queued again.
                    // Reattributed, not just confirmed: rows saved while
                    // offline carry `authorID = local-...`, and a
                    // placeholder left on the head row also blocks the
                    // stamp below, which needs the field empty.
                    await TableIdentity.confirmAndReattribute(in: container.mainContext)
                    // Which household this phone is in, asked before the
                    // stamp below decides the rows are unshared and its
                    // own. The cache is per device, so the second device
                    // of an Apple ID that joined on the first has no local
                    // trace of the join until this runs.
                    let wasSolo = HouseholdShare.membership == .solo
                    let membership = await HouseholdShare.refreshMembership()
                    if wasSolo, case .member = membership {
                        HouseholdSync.adoptMySeat(in: container.mainContext)
                    }
                    HouseholdSync.stampIdentityIfUnshared(in: container.mainContext)
                    HouseholdSync.sweep(in: container.mainContext)
                    #if DEBUG && targetEnvironment(simulator)
                    // Rehearsal: a household arriving from "Sam", so the
                    // member's view, the notices and the roster can be
                    // photographed without a second Apple ID. Writes real
                    // rows and sets membership, so never on a phone.
                    if LaunchFlags.consume("-plated-rehearse-household") {
                        try? await Task.sleep(for: .seconds(2))
                        await HouseholdSync.rehearse(context: container.mainContext)
                    }
                    #endif
                    #if DEBUG && targetEnvironment(simulator)
                    // Rehearsal: a delivery that never came from CloudKit,
                    // so the banners, the bell rows and the actions can be
                    // looked at on a simulator. Writes a real post by
                    // "Riley" into the mirrored store and spends the one
                    // permission prompt, so it is compiled out of every
                    // phone build, `make phone` included.
                    if LaunchFlags.consume("-plated-fake-table-news") {
                        try? await Task.sleep(for: .seconds(2))
                        await TableNews.rehearse(context: container.mainContext)
                    }
                    // Spend the one permission prompt now, for a simulator
                    // that has never planned a night. Never on a phone.
                    if LaunchFlags.consume("-plated-ask-notifications") {
                        try? await Task.sleep(for: .seconds(1))
                        let granted = await NotificationScheduler.askOnce()
                        print("PLATED FLAG: notifications granted=\(granted)")
                    }
                    #endif
                    #if DEBUG
                    if LaunchFlags.consume("-plated-purge-cloud") {
                        do {
                            try await TableSync.purgeMirroredData()
                            print("PLATED PURGE: zone deleted, local store cleared — clean slate")
                        } catch {
                            print("PLATED PURGE FAILED: \(error)")
                        }
                        exit(0)
                    }
                    #endif
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            #if DEBUG && targetEnvironment(simulator)
            // Opt-in installed-widget verification from the in-memory fixture.
            // Never starts household sync or writes to a personal model store.
            if Self.usesPreviewContainer,
               ProcessInfo.processInfo.arguments.contains("-plated-review-widgets"),
               phase == .active || phase == .background {
                WidgetBridge.publish(from: container.mainContext)
            }
            #endif
            // Re-assert the room's lighting on every activation — a push
            // that lands during launch can otherwise flash the wrong room.
            if phase == .active {
                Self.applyRoomLighting(appearance)
            }
            // The home screen learns the week whenever the app breathes.
            if (phase == .background || phase == .active) && !Self.usesPreviewContainer {
                // And so does the household: a pass on the way in and on
                // the way out, so a night planned and the app closed goes
                // out before the phone sleeps. Preview-backed launches stay
                // wholly in memory; a foreground pull reaches PlatedStore's
                // live context and would cross the same boundary the launch
                // task above deliberately protects.
                PlanShare.schedule(reason: "scene")
                Task { @MainActor in
                    // A night the household took off while this phone was
                    // cooking it waits for the session to end, and a session
                    // ending is not a delivery: without a drain here it
                    // would sit until the zone happened to say something
                    // else. Before the widget publishes, so the home screen
                    // learns the week WITHOUT it.
                    if RemovedNights.drain(in: container.mainContext) {
                        Persist.save(container.mainContext, "nights the household took off")
                        RemovedNights.confirmDeletions()
                        // The reminder is the reason this drain exists at
                        // all: a night that has left the plan may not keep
                        // its 19:00 notice, and nothing else in this branch
                        // rebuilds them.
                        let meals = (try? container.mainContext.fetch(FetchDescriptor<PlannedMeal>())) ?? []
                        await NotificationScheduler.rebuild(meals: meals)
                    }
                    WidgetBridge.publish(from: container.mainContext)
                    // The icon's number and the bell's are one count. A row
                    // read on the iPad clears it here on the next breath,
                    // and a banner about a dish read there is withdrawn.
                    AppBadge.sync(container.mainContext)
                    if phase == .active {
                        await TableNews.reconcileDelivered(context: container.mainContext)
                        // A silent push is not delivered to an app that was
                        // force-quit, and is deferred in Low Power Mode. The
                        // next time the app is in front, it asks.
                        await TablePull.pull(reason: "foreground")
                    }
                }
            }
        }
    }
}
