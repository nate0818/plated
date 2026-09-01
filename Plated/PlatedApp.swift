import SwiftUI
import SwiftData
import UIKit

@main
struct PlatedApp: App {
    /// After Dark — the premium dark room, switched on in Home. The app never
    /// follows the system appearance; the table decides its own lighting.
    @AppStorage("afterDark") private var afterDark = false
    @Environment(\.scenePhase) private var scenePhase

    /// See PlatedStore — the app and App Intents share this one container.
    let container = PlatedStore.shared

    init() {
        BrandFonts.registerAll()
    }

    @MainActor
    private static func applyRoomLighting(dark: Bool) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = dark ? .dark : .light
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(afterDark ? .dark : .light)
                .onChange(of: afterDark) { _, dark in
                    // Belt and braces: preferredColorScheme has been seen to
                    // stick when the flip happens inside an animated binding
                    // or under a presented sheet. The UIKit override is
                    // authoritative and cannot half-apply.
                    Self.applyRoomLighting(dark: dark)
                }
                .onAppear { Self.applyRoomLighting(dark: afterDark) }
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
                Self.applyRoomLighting(dark: afterDark)
            }
            // The home screen learns the week whenever the app breathes.
            if phase == .background || phase == .active {
                Task { @MainActor in
                    WidgetBridge.publish(from: container.mainContext)
                }
            }
        }
    }
}
