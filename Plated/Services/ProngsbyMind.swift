import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The fork's language faculty. On devices with Apple Intelligence this is
/// the on-device foundation model — the same model family behind Siri:
/// private, free, and offline. Everywhere else (and whenever the model
/// declines or errors) the rule-based ProngsbyBrain answers, so the fork
/// never goes silent and never needs a server.
enum ProngsbyMind {

    /// Whether the on-device model can take this question right now.
    static var languageModelReady: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// One reply, whatever faculty is awake. The brain is both the
    /// grounding (its household snapshot rides in the instructions) and
    /// the fallback (any model trouble lands on its deterministic reply).
    static func reply(to question: String, brain: ProngsbyBrain) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.availability == .available {
            do {
                let session = LanguageModelSession(instructions: instructions(for: brain))
                let response = try await session.respond(to: question)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            } catch {
                // Guardrail refusal, context overflow, or the model being
                // busy — all land on the rule brain, never on an error string.
            }
        }
        #endif
        return brain.reply(to: question)
    }

    /// The persona and the household, compressed for the model. Facts only —
    /// the model must answer from THIS cookbook and THIS week, not invent.
    private static func instructions(for brain: ProngsbyBrain) -> String {
        var lines: [String] = []
        lines.append("""
        You are Prongsby, a talking fork: the AI cooking companion inside the \
        household meal-planning app Plated. Voice: conversational, funny, \
        quirky but smart — a genuinely useful sous chef, never a clown. Keep \
        replies short (a few sentences), no markdown headings, no bullet \
        spam. Meals get "plated", never "liked". Answer ONLY from the \
        household facts below; if something isn't there, say so plainly and \
        suggest what to do in the app instead of inventing recipes or people.
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

        if !brain.meals.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            let week = brain.meals
                .sorted { $0.date < $1.date }
                .prefix(10)
                .map { meal -> String in
                    var line = "\(formatter.string(from: meal.date)): \(meal.title)"
                    if let cook = meal.cook { line += " (\(cook.name) cooks)" }
                    return line
                }
            lines.append("The plan: " + week.joined(separator: "; ") + ".")
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
