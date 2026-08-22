import AppIntents
import SwiftData

/// "Ask Prongsby" from Siri — the fork answers by voice, grounded in the
/// household's cookbook and plan, and the exchange lands in his chat
/// thread so the conversation is waiting when the app opens.
struct AskProngsbyIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Prongsby"
    static let description = IntentDescription("Ask your cooking companion anything — dinner ideas, swaps, the week's plan.")

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

        return .result(dialog: "\(answer)")
    }
}
