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

    /// See PlatedStore — the app and App Intents share this one container.
    let container = PlatedStore.shared

    init() {
        BrandFonts.registerAll()
        Self.carryAppearanceForward()
        #if DEBUG
        // The nine steps are a scale at every content size, or the app has
        // a callout bigger than its display and nobody notices until a
        // screenshot at AX5.
        TypeScale.assertMonotone()
        #endif
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
                .task { await SyncStatus.shared.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    // Someone who just switched iCloud back on in Settings
                    // returns here; that is precisely when the warning
                    // should be re-asked rather than left stale.
                    if phase == .active {
                        Task { await SyncStatus.shared.refresh() }
                    }
                }
                .task {
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
                    if LaunchFlags.consume("-plated-prime-share") {
                        print(await TableShare.primeSchema())
                        try? await Task.sleep(for: .seconds(20))
                        exit(0)
                    }
                    #endif
                    #if DEBUG
                    if LaunchFlags.consume("-plated-prime-schema") {
                        do {
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
                Task { @MainActor in
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
