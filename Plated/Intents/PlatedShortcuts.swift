import AppIntents

/// The phrases Siri answers to without any setup.
struct PlatedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsForDinnerIntent(),
            phrases: [
                "What's for dinner in \(.applicationName)",
                "What's tonight in \(.applicationName)"
            ],
            shortTitle: "What's for Dinner",
            systemImageName: "circle.circle"
        )
        AppShortcut(
            intent: PlateTonightIntent(),
            phrases: ["Plate something tonight in \(.applicationName)"],
            shortTitle: "Plate Tonight",
            systemImageName: "plus.circle"
        )
        // Parked with the rest of Prongsby — see ProngsbyFeature. This is a
        // literal comment rather than an `if ProngsbyFeature.isEnabled`
        // because AppShortcutsBuilder does not take conditionals; restoring
        // him means uncommenting this block and flipping the flag.
        //
        // AppShortcut(
        //     intent: AskProngsbyIntent(),
        //     phrases: [
        //         "Ask Prongsby in \(.applicationName)",
        //         "Ask the fork in \(.applicationName)"
        //     ],
        //     shortTitle: "Ask Prongsby",
        //     systemImageName: "fork.knife"
        // )
    }
}
