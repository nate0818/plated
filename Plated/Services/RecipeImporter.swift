import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A recipe someone pasted in, turned into our shape.
///
/// Plain value type on purpose: nothing here touches SwiftData, so parsing
/// can happen off the main actor and the caller decides whether the result
/// is ever saved. `RecipeImportSheet` shows it for approval first — an
/// import that writes straight to the cookbook is an import you can't
/// undo when the model misreads a header.
struct ImportedRecipe: Equatable {
    var title = ""
    var summary = ""
    var servings = 4
    var prepMinutes = 0
    var cookMinutes = 0
    var ingredients: [ImportedIngredient] = []
    var steps: [String] = []

    /// Nothing worth showing. A paste of a shopping list or a URL lands here.
    var isEmpty: Bool { title.isEmpty && ingredients.isEmpty && steps.isEmpty }
}

struct ImportedIngredient: Equatable, Identifiable {
    let id = UUID()
    var name = ""
    var quantity: Double = 0
    var unit = ""
    var aisle = GroceryAisle.other.rawValue

    static func == (a: Self, b: Self) -> Bool {
        a.name == b.name && a.quantity == b.quantity && a.unit == b.unit && a.aisle == b.aisle
    }
}

/// How long the on-device model gets before the hand-written parser answers
/// instead. Longer than Prongsby's six seconds because this is a deliberate,
/// progress-indicated act the user asked for and is watching — not a chat
/// reply they expect instantly.
private let importModelDeadline: Duration = .seconds(20)

/// Paste in a recipe from anywhere — a website, a Note, a text from your
/// mother — and get back our structure.
///
/// Two faculties, same contract. On Apple Intelligence devices the
/// on-device foundation model reads the text properly: it knows that
/// "2 cups AP flour, sifted" is two cups of all-purpose flour, that a
/// blogger's childhood story is not a step, and which aisle sells za'atar.
/// Everywhere else — and whenever the model is busy, refuses, or times out
/// — `heuristic` does a decent literal job. The user always gets something
/// to correct, which is the whole point of showing it before saving.
///
/// Nothing here is network-backed. The paste never leaves the device.
enum RecipeImporter {

    static func parse(_ raw: String) async -> ImportedRecipe {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ImportedRecipe() }
        // Guardrails and context windows both dislike a whole webpage.
        let bounded = String(text.prefix(8000))

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           SystemLanguageModel.default.availability == .available,
           let smart = await generate(bounded), !smart.isEmpty {
            return smart
        }
        #endif
        return heuristic(bounded)
    }

    // MARK: The model

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    // Internal, not private: the @Generable macro synthesises a conformance
    // in an extension it cannot see into a private type.
    @Generable
    struct Draft {
        @Guide(description: "The dish's name only. Not the website, the author, or the words 'recipe' or 'print'.")
        var title: String
        @Guide(description: "One plain sentence describing the finished dish. No marketing, no story.")
        var summary: String
        @Guide(description: "How many people it serves. 4 if the text does not say.")
        var servings: Int
        @Guide(description: "Hands-on minutes before cooking starts. 0 if not stated.")
        var prepMinutes: Int
        @Guide(description: "Minutes actually cooking. 0 if not stated.")
        var cookMinutes: Int
        var ingredients: [DraftIngredient]
        @Guide(description: "The method, one instruction per element, in order. Strip any leading numbering. Omit blog commentary, tips, and nutrition notes.")
        var steps: [String]
    }

    @available(iOS 26.0, *)
    @Generable
    struct DraftIngredient {
        @Guide(description: "The food itself, singular and lowercase: 'all-purpose flour', not '2 cups AP flour, sifted'.")
        var name: String
        @Guide(description: "The amount as a number. Convert fractions: 1/2 is 0.5. Use 0 when the text gives no amount.")
        var quantity: Double
        @Guide(description: "The unit as written: cup, tbsp, g, clove. Empty string when the amount is a bare count.")
        var unit: String
        @Guide(description: "Which supermarket section sells it. Exactly one of: Produce, Meat & Seafood, Dairy & Eggs, Bakery, Pantry, Frozen, Beverages, Household, Other.")
        var aisle: String
    }

    @available(iOS 26.0, *)
    private static func generate(_ text: String) async -> ImportedRecipe? {
        // Same shape as ProngsbyMind.generate, and for the same reason: a
        // task group would await the very call the deadline is meant to
        // bound. See the note there.
        await withCheckedContinuation { (continuation: CheckedContinuation<ImportedRecipe?, Never>) in
            let gate = ImportGate()

            let work = Task {
                var result: ImportedRecipe?
                do {
                    let session = LanguageModelSession(instructions: """
                        You convert pasted recipe text into structured data.
                        Copy what the text says; never invent an ingredient, \
                        a step, or a time that is not there. If the text is \
                        not a recipe, return an empty title and no steps.
                        """)
                    let draft = try await session.respond(to: text, generating: Draft.self).content
                    result = ImportedRecipe(
                        title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        summary: draft.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                        servings: max(1, draft.servings),
                        prepMinutes: max(0, draft.prepMinutes),
                        cookMinutes: max(0, draft.cookMinutes),
                        ingredients: draft.ingredients.map {
                            ImportedIngredient(
                                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                quantity: max(0, $0.quantity),
                                unit: $0.unit.trimmingCharacters(in: .whitespacesAndNewlines),
                                // A hallucinated aisle would break the
                                // grocery sort, so only a real case counts.
                                aisle: GroceryAisle(rawValue: $0.aisle)?.rawValue
                                    ?? GroceryAisle.other.rawValue
                            )
                        }.filter { !$0.name.isEmpty },
                        steps: draft.steps
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    )
                } catch {
                    result = nil
                }
                if await gate.claim() { continuation.resume(returning: result) }
            }

            Task {
                try? await Task.sleep(for: importModelDeadline)
                if await gate.claim() {
                    continuation.resume(returning: nil)
                    work.cancel()
                }
            }
        }
    }

    private actor ImportGate {
        private var taken = false
        func claim() -> Bool {
            guard !taken else { return false }
            taken = true
            return true
        }
    }
    #endif

    // MARK: The fallback

    private static let sectionBreak = try! NSRegularExpression(
        pattern: "^\\s*(ingredients|instructions|directions|method|steps|preparation)\\s*:?\\s*$",
        options: [.caseInsensitive]
    )

    /// No model, no network — just the shape recipes almost always have:
    /// a title, an ingredients block, then a method block. Deliberately
    /// literal. It would rather hand back a slightly wrong line the cook
    /// can fix than guess and be confidently wrong.
    static func heuristic(_ text: String) -> ImportedRecipe {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return ImportedRecipe() }

        var recipe = ImportedRecipe()
        var mode = Mode.preamble
        var titled = false

        for line in lines {
            if let heading = headingKind(line) {
                mode = heading
                continue
            }
            switch mode {
            case .preamble:
                // First real line is the title; anything after it and before
                // the ingredients is the summary.
                if !titled {
                    recipe.title = line
                    titled = true
                } else if recipe.summary.isEmpty, line.count > 20 {
                    recipe.summary = line
                }
                if let n = servings(in: line) { recipe.servings = n }
                if let m = minutes(in: line, keyed: ["prep"]) { recipe.prepMinutes = m }
                if let m = minutes(in: line, keyed: ["cook", "bake", "total"]) { recipe.cookMinutes = m }
            case .ingredients:
                recipe.ingredients.append(ingredient(from: line))
            case .steps:
                recipe.steps.append(stripNumbering(line))
            }
        }

        // A paste with no headings at all: everything became preamble. Treat
        // quantity-led lines as ingredients and prose as method, which is
        // what the two actually look like.
        if recipe.ingredients.isEmpty && recipe.steps.isEmpty && lines.count > 1 {
            for line in lines.dropFirst() {
                if leadingNumber(line) != nil, line.count < 60 {
                    recipe.ingredients.append(ingredient(from: line))
                } else if line.count > 30 {
                    recipe.steps.append(stripNumbering(line))
                }
            }
        }
        return recipe
    }

    private enum Mode { case preamble, ingredients, steps }

    private static func headingKind(_ line: String) -> Mode? {
        let range = NSRange(line.startIndex..., in: line)
        guard sectionBreak.firstMatch(in: line, range: range) != nil else { return nil }
        return line.lowercased().contains("ingredient") ? .ingredients : .steps
    }

    private static func stripNumbering(_ line: String) -> String {
        var s = Substring(line)
        while let f = s.first, f.isNumber || f == "." || f == ")" || f == " " { s = s.dropFirst() }
        // "Step 3" survives the loop above; it is still not part of the step.
        let cleaned = String(s)
        return cleaned.isEmpty ? line : cleaned
    }

    /// Leading amount, including the vulgar fractions recipe sites love.
    private static func leadingNumber(_ line: String) -> (value: Double, rest: String)? {
        let fractions: [Character: Double] = [
            "½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "¼": 0.25, "¾": 0.75,
            "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875
        ]
        var whole = ""
        var idx = line.startIndex
        while idx < line.endIndex, line[idx].isNumber || line[idx] == "." {
            whole.append(line[idx]); idx = line.index(after: idx)
        }
        var value = Double(whole) ?? 0
        var found = !whole.isEmpty
        // "1 ½" and "1½" both mean one and a half.
        if idx < line.endIndex, line[idx] == " ",
           line.index(after: idx) < line.endIndex,
           let f = fractions[line[line.index(after: idx)]] {
            value += f; found = true; idx = line.index(idx, offsetBy: 2)
        } else if idx < line.endIndex, let f = fractions[line[idx]] {
            value += f; found = true; idx = line.index(after: idx)
        } else if idx < line.endIndex, line[idx] == "/",
                  case let after = line.index(after: idx), after < line.endIndex,
                  let denom = Double(String(line[after])), denom != 0 {
            value = value / denom; found = true; idx = line.index(after: after)
        }
        guard found else { return nil }
        return (value, String(line[idx...]).trimmingCharacters(in: .whitespaces))
    }

    private static let units: Set<String> = [
        "cup", "cups", "tbsp", "tablespoon", "tablespoons", "tsp", "teaspoon",
        "teaspoons", "g", "kg", "gram", "grams", "oz", "ounce", "ounces", "lb",
        "lbs", "pound", "pounds", "ml", "l", "litre", "liter", "clove", "cloves",
        "slice", "slices", "can", "cans", "pinch", "handful", "sprig", "sprigs"
    ]

    private static func ingredient(from line: String) -> ImportedIngredient {
        guard let (value, rest) = leadingNumber(line) else {
            return ImportedIngredient(name: line)
        }
        var name = rest
        var unit = ""
        if let first = rest.split(separator: " ").first,
           units.contains(String(first).lowercased()) {
            unit = String(first)
            name = String(rest.dropFirst(first.count)).trimmingCharacters(in: .whitespaces)
        }
        return ImportedIngredient(name: name, quantity: value, unit: unit)
    }

    private static func servings(in line: String) -> Int? {
        let lower = line.lowercased()
        guard lower.contains("serves") || lower.contains("serving") || lower.contains("yield")
        else { return nil }
        let digits = lower.split(whereSeparator: { !$0.isNumber })
        return digits.first.flatMap { Int($0) }
    }

    private static func minutes(in line: String, keyed keys: [String]) -> Int? {
        let lower = line.lowercased()
        guard keys.contains(where: { lower.contains($0) }), lower.contains("min") else { return nil }
        let digits = lower.split(whereSeparator: { !$0.isNumber })
        return digits.first.flatMap { Int($0) }
    }
}
