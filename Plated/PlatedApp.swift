import SwiftUI
import SwiftData

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

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(afterDark ? .dark : .light)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // The home screen learns the week whenever the app breathes.
            if phase == .background || phase == .active {
                Task { @MainActor in
                    WidgetBridge.publish(from: container.mainContext)
                }
            }
        }
    }
}
