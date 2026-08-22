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
                .task {
                    // Maintenance: wipe the private CloudKit database, print
                    // a verdict for the console, and quit. PlatedStore ran
                    // local-only this launch, so nothing re-exports. Debug
                    // only — a shipped binary carries no data-nuking flag.
                    #if DEBUG
                    if LaunchFlags.consume("-plated-purge-cloud") {
                        do {
                            try await TableSync.purgeMirroredData()
                            print("PLATED PURGE: zone deleted, private database is clean")
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
