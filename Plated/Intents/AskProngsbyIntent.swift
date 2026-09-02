import AppIntents
import SwiftData
import UIKit

/// "Ask Prongsby" from Siri — the fork answers by voice, grounded in the
/// household's cookbook and plan, and the exchange lands in his chat
/// thread so the conversation is waiting when the app opens.
struct AskProngsbyIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Prongsby"
    static let description = IntentDescription("Ask your cooking companion anything: dinner ideas, swaps, the week's plan.")

    /// Parked: keeps the fork out of the Shortcuts app and out of Siri's
    /// suggestions while ProngsbyFeature is off. The intent still compiles
    /// and still works if something already holds a shortcut to it.
    static var isDiscoverable: Bool { ProngsbyFeature.isEnabled }

    @Parameter(title: "Question", requestValueDialog: "What should I ask the fork?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PlatedStore.shared.mainContext
        let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        let members = (try? context.fetch(FetchDescriptor<HouseholdMember>())) ?? []
        let meals = (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []

        let brain = ProngsbyBrain(recipes: recipes, members: members, meals: meals)
        let answer = await ProngsbyMind.reply(to: question, brain: brain)

        // The spoken exchange is still a conversation — it belongs in the
        // thread, same as one typed into the composer.
        context.insert(DirectMessage(peerName: "Prongsby", text: question, isMine: true))
        context.insert(DirectMessage(peerName: "Prongsby", text: answer, isMine: false))
        // A voice exchange leaves a thread entry like any other; without
        // the bell it sits there unbadged and unmentioned. But only when
        // the app is away — Siri already spoke the answer, so belling a
        // foreground app badges a reply the user is looking at.
        if UIApplication.shared.applicationState != .active {
            Notifier.post(
                .prongsbyReplied, actor: "Prongsby",
                body: String(answer.prefix(120)),
                into: context
            )
        }

        // Explicitly, because Siri cold-launches this with no scene
        // attached and the process suspends the moment perform() returns —
        // nothing else would ever flush these inserts to disk.
        Persist.save(context)

        return .result(dialog: "\(answer)")
    }
}
