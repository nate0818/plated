import SwiftUI
import SwiftData
import UIKit

/// Which room the app is lit for.
///
/// This used to be a two-state switch that defaulted to light and ignored
/// the phone entirely, so somebody whose iPhone is in Dark Mode opened
/// Plated and got a white screen — and the widget, which is a separate
/// target and has always followed the system, went dark beside it. One
/// product disagreeing with itself on one Home Screen.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// nil means "whatever the phone is doing", which is the point.
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
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue

    private var appearance: Appearance {
        Appearance(rawValue: appearanceRaw) ?? .system
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
    private static let previewFlags = ["-plated-design-review", "-plated-test-groceries", "-plated-test-probe-cleanup", "-plated-test-drag-moves"]

    private static var usesPreviewContainer: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return previewFlags.contains(where: { arguments.contains($0) })
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
            if arguments.contains("-plated-design-review") && arguments.contains("-plated-review-drag") {
                PlannerDragChecks.prepareReview(in: preview.mainContext)
            }
            // Explicit UI-test fixture, inside the memory-only preview path.
            if arguments.contains("-plated-design-review") && arguments.contains("-plated-review-notifications") {
                for _ in 0..<12 {
                    preview.mainContext.insert(PlatedNotification(kind: .general, body: "A new update at your table."))
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
        Self.carryAppearanceForward()
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

    /// Somebody who deliberately turned the dark room on keeps it. Everybody
    /// else joins the phone, which is what a fresh install now gives them and
    /// what the widget has been doing all along. Runs once: after this the
    /// `appearance` key exists and the old switch is never read again.
    private static func carryAppearanceForward() {
        let store = UserDefaults.standard
        guard store.string(forKey: "appearance") == nil else { return }
        let wasDark = store.bool(forKey: "afterDark")
        store.set(wasDark ? Appearance.dark.rawValue : Appearance.system.rawValue,
                  forKey: "appearance")
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
                    await SyncStatus.shared.refresh()
                    await TableShare.removeSchemaProbes(from: container.mainContext)
                }
                .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                    // Every planner edit ends in a save, most of them
                    // through autosave with no call site to hook. Three
                    // seconds after the last one, the plan goes out.
                    PlanShare.schedule(reason: "save")
                }
                .onReceive(NotificationCenter.default.publisher(for: PlanLedger.nightsDropped)) { _ in
                    // Nights left the ledger with no delivery to rebuild
                    // the reminders through: a leave, a flip, an identity
                    // reset. Without this the 19:00 "Your night tomorrow"
                    // for a table this phone is no longer at fires anyway,
                    // until somebody opens the Plan tab.
                    Task { @MainActor in await NotificationScheduler.rebuild(from: container.mainContext) }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Someone who just switched iCloud back on in Settings
                    // returns here; that is precisely when the warning
                    // should be re-asked rather than left stale.
                    if phase == .active {
                        Task {
                            await SyncStatus.shared.refresh()
                            await TableShare.removeSchemaProbes(from: container.mainContext)
                        }
                    }
                }
                .task {
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
            // Re-assert the room's lighting on every activation — a push
            // that lands during launch can otherwise flash the wrong room.
            if phase == .active {
                Self.applyRoomLighting(appearance)
            }
            // The home screen learns the week whenever the app breathes.
            if phase == .background || phase == .active {
                // And so does the household: a pass on the way in and on
                // the way out, so a night planned and the app closed goes
                // out before the phone sleeps.
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
