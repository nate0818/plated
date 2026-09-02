import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The fork's language faculty. On devices with Apple Intelligence this is
/// the on-device foundation model — the same model family behind Siri:
/// private, free, and offline. Everywhere else (and whenever the model
/// declines or errors) the rule-based ProngsbyBrain answers, so the fork
/// never goes silent and never needs a server.
/// How long the on-device model gets before the rule brain takes over.
/// Without a bound, a request that never returns leaves `session.thinking`
/// stuck true for the life of the app — and that flag is shell-owned, so
/// the composer's `guard !session.thinking` would wedge the chat for good.
private let prongsbyModelDeadline: Duration = .seconds(6)

/// Main-actor by declaration, not by luck. `ProngsbyBrain` holds `@Model`
/// objects from the shared main context, and this type reads their
/// persisted properties and walks their relationships. In Swift 5 mode a
/// plain `nonisolated async func` awaited from the main actor hops to the
/// cooperative pool (SE-0338), which put those reads — and the relationship
/// faults behind `sortedIngredients` and `meal.cook` — on a background
/// thread while `@Query` refreshed the same context on main.
@MainActor
enum ProngsbyMind {

    /// One reply, whatever faculty is awake. The brain is both the
    /// grounding (its household snapshot rides in the instructions) and
    /// the fallback (any model trouble lands on its deterministic reply).
    static func reply(to question: String, brain: ProngsbyBrain) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), hasFacts(brain),
           SystemLanguageModel.default.availability == .available {
            // Built here, on the actor, before any suspension point: what
            // crosses into the generator is a finished String, never a
            // model object.
            let grounding = instructions(for: brain)
            if let text = await generate(question, grounding: grounding), !text.isEmpty {
                return text
            }
        }
        #endif
        return brain.reply(to: question)
    }

    /// An empty house has nothing to ground an answer in, and "answer ONLY
    /// from the facts below" with no facts below invites the model to
    /// either refuse or invent. The rule brain has real onboarding lines
    /// for that case.
    private static func hasFacts(_ brain: ProngsbyBrain) -> Bool {
        !brain.recipes.isEmpty || !brain.members.isEmpty || !brain.meals.isEmpty
    }

    #if canImport(FoundationModels)
    /// The generation itself, off the actor so a slow model never blocks
    /// the main thread — safe because only Strings cross the boundary.
    ///
    /// **Not a task group, deliberately.** `withTaskGroup` awaits every
    /// child before it returns, `cancelAll()` included — so if
    /// `respond(to:)` does not honour cancellation (and nothing promises it
    /// does), a group-based race gives you a deadline that expires while
    /// the group sits there waiting for the very call it was meant to
    /// bound. Same shape as the bug we fixed in CloudSync: a timeout that
    /// does not bound the thing it guards. Two independent tasks through
    /// one continuation lets the deadline actually win and leaves the
    /// model's task to finish unobserved.
    @available(iOS 26.0, *)
    private nonisolated static func generate(_ question: String, grounding: String) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let gate = FirstPast()

            let work = Task {
                let text: String?
                do {
                    // A fresh session per question on purpose: the
                    // instructions carry a snapshot of this household's
                    // cookbook and plan, and a reused session would answer
                    // tonight's question from last week's facts.
                    let session = LanguageModelSession(instructions: grounding)
                    text = try await session.respond(to: question)
                        .content.trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    // Guardrail refusal, context overflow, or the model
                    // being busy — all land on the rule brain, never on
                    // an error string.
                    text = nil
                }
                if await gate.claim() { continuation.resume(returning: text) }
            }

            Task {
                try? await Task.sleep(for: prongsbyModelDeadline)
                if await gate.claim() {
                    continuation.resume(returning: nil)
                    // Ask nicely; the answer above does not depend on it.
                    work.cancel()
                }
            }
        }
    }

    /// Lets exactly one of two racers resume the continuation. Resuming a
    /// checked continuation twice is a crash, not a warning.
    private actor FirstPast {
        private var taken = false
        func claim() -> Bool {
            guard !taken else { return false }
            taken = true
            return true
        }
    }
    #endif

    /// The persona and the household, compressed for the model. Facts only —
    /// the model must answer from THIS cookbook and THIS week, not invent.
    private static func instructions(for brain: ProngsbyBrain) -> String {
        var lines: [String] = []
        lines.append("""
        You are Prongsby, a talking fork: the AI cooking companion inside the \
        household meal-planning app Plated. Voice: conversational, funny, \
        quirky but smart, a genuinely useful sous chef and never a clown. \
        Keep replies short (a few sentences), no markdown headings, no \
        bullet spam. Meals get "plated", never "liked". Answer ONLY from the \
        household facts below; if something isn't there, say so plainly and \
        suggest what to do in the app instead of inventing recipes or people.

        PUNCTUATION, strictly: never use an em dash or an en dash. Not one, \
        anywhere, for any reason. Use a full stop, a comma or a colon \
        instead. Rewrite the sentence rather than reaching for a dash.
        """)

        if !brain.members.isEmpty {
            lines.append("Household: " + brain.members.map { member in
                member.cookWeekdays.isEmpty
                    ? member.name
                    : "\(member.name) (cooks \(weekdayNames(member.cookWeekdays)))"
            }.joined(separator: ", ") + ".")
        }

        if !brain.recipes.isEmpty {
            let dishes = brain.recipes.prefix(40).map { recipe -> String in
                var bits = [recipe.title]
                if recipe.totalMinutes > 0 { bits.append("\(recipe.totalMinutes) min") }
                bits.append(recipe.difficultyValue.rawValue)
                return bits.joined(separator: ", ")
            }
            lines.append("Cookbook (\(brain.recipes.count) dishes): " + dishes.joined(separator: " · ") + ".")
        }

        // Bounded HERE rather than at the fetch, because both callers pass
        // everything: the Siri intent fetches PlannedMeal with no predicate
        // and the chat view uses a bare @Query. Nothing prunes past meals,
        // so an ascending sort with `prefix(10)` handed the model the ten
        // OLDEST dinners this household ever planned — and past the
        // eleventh, the plan block contained no upcoming night at all,
        // directly under an instruction reading "answer ONLY from the
        // facts below". Every other PlannedMeal consumer in the app bounds
        // its window; this was the one that didn't, and it was the one
        // feeding the model.
        let today = Calendar.current.startOfDay(for: .now)
        let upcoming = brain.meals
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
            .prefix(10)
        if !upcoming.isEmpty {
            let formatter = DateFormatter()
            // A real date, not a bare weekday: "Monday: Chili" from six
            // weeks ago is indistinguishable from this Monday, and the
            // model has no way to notice.
            formatter.dateFormat = "EEEE d MMMM"
            let week = upcoming.map { meal -> String in
                var line = "\(formatter.string(from: meal.date)): \(meal.title)"
                if Calendar.current.isDateInToday(meal.date) { line += " (tonight)" }
                if let cook = meal.cook { line += " (\(cook.name) cooks)" }
                return line
            }
            lines.append("The plan, from today onward: " + week.joined(separator: "; ") + ".")
        }

        return lines.joined(separator: "\n\n")
    }

    private static func weekdayNames(_ weekdays: [Int]) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return weekdays.compactMap { day in
            symbols.indices.contains(day - 1) ? symbols[day - 1] : nil
        }.joined(separator: "/")
    }
}
