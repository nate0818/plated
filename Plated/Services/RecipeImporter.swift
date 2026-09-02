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

        let literal = heuristic(bounded)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           SystemLanguageModel.default.availability == .available,
           let smart = await generate(bounded), !smart.isEmpty {
            return reconcile(smart, with: literal)
        }
        #endif
        return literal
    }

    /// The model's answer, with the literal parser's answer used to fill any
    /// hole the model left.
    ///
    /// This used to be winner-takes-all, and the model won whenever it
    /// returned anything at all — including the case that actually bit:
    /// a confident title and summary with an EMPTY ingredient list. The
    /// cook then landed in a cookbook entry named after their paste with
    /// nothing under Ingredients, which is the worst of both parsers rather
    /// than the best. Neither faculty is reliably better per FIELD, so the
    /// merge is per field: prefer the model where it spoke, fall back to
    /// the literal read where it didn't, and never let either one hand back
    /// a paragraph as a title.
    static func reconcile(_ smart: ImportedRecipe, with literal: ImportedRecipe) -> ImportedRecipe {
        var out = smart
        out.title = sanitizedTitle(smart.title) ?? sanitizedTitle(literal.title) ?? ""
        if out.summary.isEmpty { out.summary = literal.summary }
        if out.ingredients.isEmpty { out.ingredients = literal.ingredients }
        if out.steps.isEmpty { out.steps = literal.steps }
        if out.prepMinutes == 0 { out.prepMinutes = literal.prepMinutes }
        if out.cookMinutes == 0 { out.cookMinutes = literal.cookMinutes }
        return out
    }

    /// A title, or nothing — never a paragraph.
    ///
    /// The complaint that started this was "it chose the name from the first
    /// few sentences of the pasted recipe", and the guard belongs here
    /// rather than in either parser: both can produce prose, and a wrong
    /// name is worse than no name. No name becomes a question at the review
    /// step, which the cook answers in one tap.
    static func sanitizedTitle(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: CharacterSet(charactersIn: "#*_ \t"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains("\n") else { return nil }
        // One clause. A title that runs into a second sentence is prose that
        // happened to be first on the page.
        let firstSentence = t.components(separatedBy: ". ").first ?? t
        let candidate = firstSentence == t ? t : firstSentence
        guard candidate.count <= 70, candidate.split(separator: " ").count <= 12
        else { return nil }
        // "Ingredients" is what the paste is ABOUT to list, not what the
        // dish is called. Reachable from either parser.
        let key = candidate.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        guard !ingredientHeadings.contains(key), !stepHeadings.contains(key),
              !ignoredHeadings.contains(key) else { return nil }
        return candidate
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
        @Guide(description: "One plain sentence describing the finished dish. No marketing, no story. Never use an em dash or an en dash; use a comma or a full stop.")
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
                        Never write an em dash or an en dash in any field.
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

    /// One line of a paste, stripped of the decoration people bring with
    /// them — markdown, bullets, step numbers — with what that decoration
    /// MEANT kept as flags.
    ///
    /// The old parser kept the decoration and threw away the meaning, which
    /// is exactly backwards, and is why a ChatGPT paste came out inverted.
    /// "- 4 chicken breasts" has no LEADING digit, so it failed the
    /// quantity test and fell through a length test into the method;
    /// "1. Season the chicken" DOES lead with a digit, so it became an
    /// ingredient — one unit of ". Season the chicken". Ingredients became
    /// steps and steps became ingredients, every time, for every list any
    /// chatbot or recipe site has ever produced.
    ///
    /// Strip the bullet and the step number FIRST, remember which one you
    /// stripped, and both questions answer themselves.
    private struct Line {
        var text: String
        /// Came off a "-", "•", "*" list. Says "this is an item".
        var isBullet = false
        /// Came off a "1." / "1)" list. Says "this is a step".
        var stepNumber: Int?
        /// Wore "#" or "**". Says "this is a header", not content.
        var wasDecorated = false
    }

    private static let bullets: Set<Character> = ["-", "–", "—", "•", "*", "+", "‣", "·", "◦", "▪", "▸", "›"]

    private static func readLines(_ text: String) -> [Line] {
        text.components(separatedBy: .newlines).compactMap { raw -> Line? in
            var s = raw.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return nil }
            var line = Line(text: s)

            while s.hasPrefix(">") {
                s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            let hashes = s.prefix { $0 == "#" }.count
            if hashes > 0, hashes <= 6 {
                s = String(s.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
                line.wasDecorated = true
            }

            // "*" is a bullet at the start of a line and emphasis around a
            // word. "**Ingredients**" is the second, and has to be unwrapped
            // BEFORE bullets are considered — otherwise the heading is read
            // as a bullet holding "*Ingredients*", the section is never
            // entered, and every ingredient below it lands somewhere else.
            if let bare = unwrapped(s) {
                s = bare
                line.wasDecorated = true
            } else if let first = s.first, bullets.contains(first) {
                let rest = String(s.dropFirst())
                if rest.isEmpty || rest.hasPrefix(" ") || rest.hasPrefix("\t") {
                    s = rest.trimmingCharacters(in: .whitespaces)
                    line.isBullet = true
                }
            }
            if let (number, rest) = stepNumbering(s) {
                line.stepNumber = number
                s = rest
            }
            for box in ["[ ]", "[]", "[x]", "[X]", "▢", "☐", "◻︎", "□"] where s.hasPrefix(box) {
                s = String(s.dropFirst(box.count)).trimmingCharacters(in: .whitespaces)
                line.isBullet = true
            }

            s = s.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .trimmingCharacters(in: .whitespaces)
            line.text = s
            return s.isEmpty ? nil : line
        }
    }

    /// "**Ingredients**" → "Ingredients", and nil when the line is not
    /// wrapped end to end (so "- **chicken** thighs" keeps its bullet).
    private static func unwrapped(_ s: String) -> String? {
        for mark in ["***", "**", "__", "*", "_"] where s.hasPrefix(mark) && s.hasSuffix(mark)
            && s.count > mark.count * 2 {
            return String(s.dropFirst(mark.count).dropLast(mark.count))
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// "1. Season the chicken" → (1, "Season the chicken").
    ///
    /// The whitespace after the dot is load-bearing: without it "1.5 cups
    /// flour" reads as step one of a method called "5 cups flour".
    private static func stepNumbering(_ s: String) -> (Int, String)? {
        var digits = ""
        var idx = s.startIndex
        while idx < s.endIndex, s[idx].isNumber, digits.count < 2 {
            digits.append(s[idx]); idx = s.index(after: idx)
        }
        guard !digits.isEmpty, idx < s.endIndex, s[idx] == "." || s[idx] == ")" else {
            // "Step 3 — sear the chicken" wears its numbering in words.
            let lower = s.lowercased()
            guard lower.hasPrefix("step ") else { return nil }
            let after = s.dropFirst(5).drop { $0.isNumber || $0 == ":" || $0 == "." || $0 == "-" || $0 == "—" || $0 == " " }
            let rest = String(after).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : (Int(s.dropFirst(5).prefix { $0.isNumber }) ?? 0, rest)
        }
        let after = s.index(after: idx)
        guard after < s.endIndex, s[after] == " " || s[after] == "\t" else { return nil }
        let rest = String(s[after...]).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : (Int(digits) ?? 0, rest)
    }

    // MARK: Headings

    private enum Section { case preamble, ingredients, steps, ignored }

    private static let ingredientHeadings = [
        "ingredients", "ingredient", "ingredient list", "the ingredients",
        "what you need", "what you'll need", "what youll need", "you'll need",
        "you will need", "youll need", "shopping list", "grocery list"
    ]
    private static let stepHeadings = [
        "instructions", "instruction", "directions", "direction", "method",
        "the method", "steps", "the steps", "preparation", "procedure",
        "how to make it", "how to make", "how to", "to make", "directions:",
        "cooking instructions"
    ]
    /// Everything a recipe page wraps around the recipe. Naming these is how
    /// the paste box's promise — "the blogger's childhood story, we'll drop
    /// the rest" — is actually kept.
    private static let ignoredHeadings = [
        "notes", "note", "tips", "tip", "tips and tricks", "chef's notes",
        "cook's notes", "nutrition", "nutrition facts", "nutrition information",
        "equipment", "you might also like", "storage", "how to store",
        "variations", "substitutions", "faq", "frequently asked questions",
        "serving suggestions", "what to serve with it", "make ahead",
        "leftovers", "why you'll love it", "why youll love it",
        "about this recipe", "reviews", "comments", "related recipes"
    ]

    /// The section a heading opens, plus anything written after its colon —
    /// "Ingredients: 2 cups flour, 1 tsp salt" is a heading AND a line.
    private static func heading(_ line: Line) -> (Section, inline: String)? {
        let text = line.text
        guard text.count <= 60, line.stepNumber == nil else { return nil }

        let head: String
        var inline = ""
        if let colon = text.firstIndex(of: ":") {
            head = String(text[..<colon])
            inline = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        } else {
            head = text
        }
        let key = head.trimmingCharacters(in: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard !key.isEmpty else { return nil }

        if ingredientHeadings.contains(key) { return (.ingredients, inline) }
        if stepHeadings.contains(key) { return (.steps, inline) }
        if ignoredHeadings.contains(key) { return (.ignored, "") }
        // "For the sauce", "For the marinade" — a sub-list of ingredients,
        // and the most common way a recipe opens one without saying so.
        if key.hasPrefix("for the ") || key.hasPrefix("for ") , key.count < 40, line.isBullet == false {
            return (.ingredients, inline)
        }
        return nil
    }

    // MARK: The parse

    /// No model, no network — just the shape recipes almost always have:
    /// a name, a list of things, then a list of instructions. Deliberately
    /// literal. It would rather hand back a slightly wrong line the cook
    /// can fix than guess and be confidently wrong.
    static func heuristic(_ text: String) -> ImportedRecipe {
        let lines = readLines(text)
        guard !lines.isEmpty else { return ImportedRecipe() }

        var recipe = ImportedRecipe()
        var mode = Section.preamble
        var preamble: [Line] = []
        var sawHeading = false

        for line in lines {
            if let (section, inline) = heading(line) {
                mode = section
                sawHeading = true
                if !inline.isEmpty, section == .ingredients {
                    for part in splitIngredientBlock(inline) {
                        recipe.ingredients.append(parseIngredientLine(part))
                    }
                } else if !inline.isEmpty, section == .steps {
                    recipe.steps.append(inline)
                }
                continue
            }
            switch mode {
            case .preamble:
                preamble.append(line)
            case .ingredients:
                // A paragraph inside an ingredient list is a note about the
                // list, not an item.
                guard line.text.count <= 140 else { continue }
                for part in splitIngredientBlock(line.text) {
                    recipe.ingredients.append(parseIngredientLine(part))
                }
            case .steps:
                append(line, to: &recipe.steps)
            case .ignored:
                continue
            }
        }

        // No headings at all — a bare list pasted out of a chat window, which
        // is the single most common paste there is. Read each line on its own
        // merits instead.
        var consumed = Set<String>()
        if !sawHeading || (recipe.ingredients.isEmpty && recipe.steps.isEmpty) {
            let body = sawHeading ? lines : Array(lines.dropFirst(preambleTitleCount(preamble)))
            for line in body {
                if looksLikeStep(line) {
                    append(line, to: &recipe.steps)
                    consumed.insert(line.text)
                } else if looksLikeIngredient(line) {
                    for part in splitIngredientBlock(line.text) {
                        recipe.ingredients.append(parseIngredientLine(part))
                    }
                    consumed.insert(line.text)
                }
            }
        }

        recipe.title = title(from: preamble.isEmpty ? lines : preamble)
        recipe.summary = summary(from: preamble, excluding: recipe.title, consumed: consumed)
        for line in preamble {
            for fragment in factFragments(line.text) {
                if let n = servings(in: fragment) { recipe.servings = n }
                if let m = minutes(in: fragment, keyed: ["prep"]) { recipe.prepMinutes = m }
                if let m = minutes(in: fragment, keyed: ["cook", "bake", "roast"]) { recipe.cookMinutes = m }
            }
        }
        recipe.ingredients = recipe.ingredients.filter { !$0.name.isEmpty }
        recipe.steps = recipe.steps.filter { !$0.isEmpty }
        return recipe
    }

    /// Adds a line to the method, or continues the previous instruction.
    ///
    /// A step that wraps is one step. On a scanned card every visual row
    /// arrives as its own line, so "Whisk the cornmeal, flour, sugar,
    /// baking powder / and salt together in a large bowl" came back as two
    /// steps, the second of which begins with "and". Same shape wherever
    /// text was wrapped to a column before it was copied.
    ///
    /// The tell is punctuation: an instruction that has ended, ends. A line
    /// carrying no number of its own, following one that did not finish its
    /// sentence, is the rest of that sentence.
    private static func append(_ line: Line, to steps: inout [String]) {
        // A short line ending in a colon is a heading, not an instruction —
        // "Add the sauce:", "Serve:", "Optional crispy finish:". Left alone
        // it becomes a numbered step that tells the cook to do nothing,
        // and pushes the real instruction to the next number. It belongs
        // to the step it introduces, so it takes it.
        if let previous = steps.last, isHeading(previous) {
            steps[steps.count - 1] = previous + " " + line.text
            return
        }
        guard line.stepNumber == nil, !line.isBullet, let previous = steps.last,
              !previous.hasSuffix("."), !previous.hasSuffix("!"),
              !previous.hasSuffix("?"), !previous.hasSuffix(":")
        else {
            steps.append(line.text)
            return
        }
        steps[steps.count - 1] = previous + " " + line.text
    }

    /// A label introducing what follows, rather than a sentence that
    /// happens to end in a colon. Length is the tell: real instructions
    /// that end in a colon run long ("Combine the following in a bowl:").
    private static func isHeading(_ text: String) -> Bool {
        text.hasSuffix(":") && text.count <= 40
    }

    private static func preambleTitleCount(_ preamble: [Line]) -> Int {
        preamble.isEmpty ? 0 : 1
    }

    private static func looksLikeStep(_ line: Line) -> Bool {
        if line.stepNumber != nil { return true }
        if line.isBullet { return false }
        let t = line.text
        guard leadingAmount(t) == nil else { return false }
        // A sentence with a verb's worth of length. Ingredient lines that
        // reach this length are almost always prose about the ingredient.
        return t.count >= 45 && t.contains(" ")
    }

    private static func looksLikeIngredient(_ line: Line) -> Bool {
        if line.stepNumber != nil { return false }
        let t = line.text
        guard t.count <= 110 else { return false }
        if leadingAmount(t) != nil { return true }
        // A bullet with no amount is still an item — "Salt and pepper to
        // taste", "Olive oil" — as long as it reads like a thing rather
        // than a sentence about one.
        return line.isBullet && t.split(separator: " ").count <= 10 && !t.hasSuffix(".")
    }

    // MARK: Title

    private static let metadataLeaders = [
        "serves", "serving", "yield", "makes", "prep", "cook", "total",
        "active", "course", "cuisine", "calories", "by ", "author",
        "print", "rated", "difficulty", "category", "keyword", "time"
    ]

    /// The dish's name, or nothing at all.
    ///
    /// "Nothing at all" is a real answer and the important one. The old
    /// parser took the first line whatever it was, so pasting a recipe that
    /// opens with prose named the dish after a paragraph, and pasting one
    /// that opens with "Ingredients" named it "Ingredients". An empty title
    /// is honest, and the review step turns it into a question — which is
    /// a far better experience than a wrong answer the cook has to notice
    /// before they can fix it.
    private static func title(from lines: [Line]) -> String {
        // An explicit header wins: "# Creamy Tuscan Chicken".
        if let decorated = lines.first(where: { $0.wasDecorated && heading($0) == nil }),
           let name = titleShaped(decorated) {
            return name
        }
        for line in lines.prefix(6) {
            if let name = titleShaped(line) { return name }
        }
        return ""
    }

    private static func titleShaped(_ line: Line) -> String? {
        guard line.stepNumber == nil, !line.isBullet, heading(line) == nil else { return nil }
        let t = line.text.trimmingCharacters(in: CharacterSet(charactersIn: "#*_ "))
        guard !t.isEmpty, t.count <= 70 else { return nil }
        guard t.split(separator: " ").count <= 12 else { return nil }
        // Two sentences is prose. One sentence ending in a full stop, with
        // more than a title's worth of words, is prose too.
        guard !t.contains(". ") else { return nil }
        if t.hasSuffix("."), t.split(separator: " ").count > 6 { return nil }
        guard leadingAmount(t) == nil else { return nil }
        let lower = t.lowercased()
        guard !metadataLeaders.contains(where: { lower.hasPrefix($0) }) else { return nil }
        return t
    }

    /// The one-line description, if the paste offered one.
    ///
    /// `consumed` is what the no-heading sweep already turned into a step or
    /// an ingredient. Without it the summary is the first instruction —
    /// every photoless import opened with "Melt the butter in a wide
    /// skillet" printed under its own title as though it described the dish.
    private static func summary(
        from preamble: [Line], excluding title: String, consumed: Set<String>
    ) -> String {
        for line in preamble where line.text != title && !consumed.contains(line.text) {
            let t = line.text
            guard t.count >= 40, t.count <= 240, t.contains(" ") else { continue }
            guard leadingAmount(t) == nil, line.stepNumber == nil else { continue }
            let lower = t.lowercased()
            guard !metadataLeaders.contains(where: { lower.hasPrefix($0) }) else { continue }
            return t
        }
        return ""
    }

    // MARK: Ingredients

    /// A block of ingredients as one string → one string per ingredient.
    ///
    /// Copying a list out of a chat window very often arrives as a single
    /// run of text, either newline-joined or comma-joined. Both are lists;
    /// neither is one ingredient called all of it.
    static func splitIngredientBlock(_ raw: String) -> [String] {
        let byLine = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if byLine.count > 1 { return byLine.flatMap(splitInlineBullets) }

        let single = byLine.first ?? ""
        let inline = splitInlineBullets(single)
        if inline.count > 1 { return inline }

        // "2 cups flour, 1 tsp salt, 3 eggs" — split only where the next
        // fragment starts with its own amount, so "garlic, minced" and
        // "salt and pepper, to taste" stay whole.
        let parts = single.components(separatedBy: ",")
        guard parts.count > 2 else { return [single] }
        var out: [String] = []
        for part in parts {
            let piece = part.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }
            if leadingAmount(piece) != nil || out.isEmpty {
                out.append(piece)
            } else {
                out[out.count - 1] += ", " + piece
            }
        }
        return out.count > 1 ? out : [single]
    }

    private static func splitInlineBullets(_ s: String) -> [String] {
        for mark in [" • ", " · ", " ‣ ", "; "] where s.contains(mark) {
            let parts = s.components(separatedBy: mark)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if parts.count > 1 { return parts }
        }
        return [s]
    }

    private static let units: [String: String] = {
        let canonical: [String: [String]] = [
            "cup": ["cup", "cups", "c"],
            "tbsp": ["tbsp", "tbsps", "tbs", "tablespoon", "tablespoons", "T"],
            "tsp": ["tsp", "tsps", "teaspoon", "teaspoons", "t"],
            "g": ["g", "gram", "grams", "gm"],
            "kg": ["kg", "kilogram", "kilograms"],
            "oz": ["oz", "ounce", "ounces"],
            "lb": ["lb", "lbs", "pound", "pounds"],
            "ml": ["ml", "millilitre", "milliliter", "millilitres", "milliliters"],
            "l": ["l", "litre", "liter", "litres", "liters"],
            "clove": ["clove", "cloves"],
            "slice": ["slice", "slices"],
            "can": ["can", "cans"],
            "jar": ["jar", "jars"],
            "bottle": ["bottle", "bottles"],
            "bunch": ["bunch", "bunches"],
            "sprig": ["sprig", "sprigs"],
            "stalk": ["stalk", "stalks"],
            "head": ["head", "heads"],
            "pinch": ["pinch", "pinches"],
            "handful": ["handful", "handfuls"],
            "package": ["package", "packages", "pkg", "packet", "packets"],
            "stick": ["stick", "sticks"],
            "quart": ["quart", "quarts", "qt"],
            "pint": ["pint", "pints", "pt"],
            "gallon": ["gallon", "gallons", "gal"],
            "dash": ["dash", "dashes"],
        ]
        var map: [String: String] = [:]
        for (key, spellings) in canonical {
            for spelling in spellings { map[spelling.lowercased()] = key }
        }
        return map
    }()

    /// Words that describe what was DONE to the ingredient, not what to buy.
    /// Trimmed so the grocery list can merge "garlic, minced" with "garlic".
    private static let prepNotes: Set<String> = [
        "minced", "chopped", "finely chopped", "roughly chopped", "diced",
        "sliced", "thinly sliced", "grated", "shredded", "crushed", "cubed",
        "melted", "softened", "room temperature", "at room temperature",
        "divided", "drained", "rinsed", "drained and rinsed", "beaten",
        "peeled", "peeled and diced", "peeled and chopped", "trimmed",
        "to taste", "for serving", "for garnish", "plus more for serving",
        "plus more", "optional", "packed", "lightly packed", "halved",
        "quartered", "julienned", "zested", "juiced", "toasted", "rinsed and drained",
    ]

    /// One written ingredient → our three fields.
    ///
    /// Shared with the recipe editor's "add one" field on purpose. Two
    /// parsers meant the same typing produced different rows depending on
    /// which door it came through — the editor's could not read a fraction
    /// at all, so "1 ½ cups flour" became an ingredient literally named
    /// "1 ½ cups flour" with no quantity, and it never reached the grocery
    /// list's merge.
    static func parseIngredientLine(_ raw: String) -> ImportedIngredient {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if let first = s.first, bullets.contains(first) {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        s = s.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespaces)
        while s.hasSuffix(".") { s = String(s.dropLast()).trimmingCharacters(in: .whitespaces) }
        guard !s.isEmpty else { return ImportedIngredient() }

        guard let (quantity, rest0) = leadingAmount(s) else {
            let name = cleanedName(s)
            return ImportedIngredient(name: name, quantity: 0, unit: "",
                                      aisle: aisle(for: name).rawValue)
        }

        var rest = rest0
        // "1-2 cloves", "1 to 2 cloves" — take the lower bound and move on.
        for joiner in ["-", "–", "—", "to "] where rest.hasPrefix(joiner) {
            let tail = String(rest.dropFirst(joiner.count)).trimmingCharacters(in: .whitespaces)
            if let (_, after) = leadingAmount(tail) { rest = after }
            break
        }

        // "1 (14.5 oz) can diced tomatoes" — the size belongs to the name.
        var parenthetical = ""
        if rest.hasPrefix("("), let close = rest.firstIndex(of: ")") {
            parenthetical = String(rest[rest.index(after: rest.startIndex)..<close])
            rest = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }

        var unit = ""
        let tokens = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if let head = tokens.first {
            let key = String(head).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if let canonical = units[key] {
                unit = canonical
                rest = tokens.count > 1 ? String(tokens[1]).trimmingCharacters(in: .whitespaces) : ""
            }
        }
        if rest.lowercased().hasPrefix("of ") {
            rest = String(rest.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }

        var name = cleanedName(rest)
        if !parenthetical.isEmpty {
            name = name.isEmpty ? parenthetical : "\(name) (\(parenthetical))"
        }
        if name.isEmpty { name = cleanedName(s) }
        return ImportedIngredient(name: name, quantity: quantity, unit: unit,
                                  aisle: aisle(for: name).rawValue)
    }

    /// Drops the trailing clause that says what to do to it rather than
    /// what it is. Conservative: only a known preparation, only at the end.
    private static func cleanedName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespaces)
        while let comma = name.lastIndex(of: ",") {
            let tail = String(name[name.index(after: comma)...])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            guard prepNotes.contains(tail) else { break }
            name = String(name[..<comma]).trimmingCharacters(in: .whitespaces)
        }
        return name.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
    }

    /// A digit you can do arithmetic with.
    ///
    /// `Character.isNumber` is true for "½" — it is a Number in Unicode's
    /// eyes — so the plain check swallowed the vulgar fraction into the
    /// whole-number run, `Double("½")` returned nil, and every "½ cup" in
    /// every recipe on the internet imported with no amount at all.
    private static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    /// Leading amount, including the vulgar fractions recipe sites love and
    /// the mixed numbers everyone writes by hand.
    private static func leadingAmount(_ line: String) -> (value: Double, rest: String)? {
        let fractions: [Character: Double] = [
            "½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "¼": 0.25, "¾": 0.75,
            "⅕": 0.2, "⅖": 0.4, "⅗": 0.6, "⅘": 0.8, "⅙": 1.0 / 6, "⅚": 5.0 / 6,
            "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875
        ]
        var whole = ""
        var idx = line.startIndex
        while idx < line.endIndex, isDigit(line[idx]) || line[idx] == "." {
            whole.append(line[idx]); idx = line.index(after: idx)
        }
        // A step number that slipped through is not an amount.
        if whole.hasSuffix("."), idx < line.endIndex, line[idx] == " " { return nil }
        var value = Double(whole) ?? 0
        var found = !whole.isEmpty

        if idx < line.endIndex, line[idx] == "/" {
            // "1/2 cup" — what came before the slash was the numerator.
            let after = line.index(after: idx)
            var denom = ""
            var cursor = after
            while cursor < line.endIndex, isDigit(line[cursor]) {
                denom.append(line[cursor]); cursor = line.index(after: cursor)
            }
            if let d = Double(denom), d != 0 {
                // A MIXED NUMBER THAT LOST ITS SPACE. OCR reads "1 1/2 cups"
                // off a card as "11/2 cups" all the time — the gap between
                // the whole number and the numerator is a few pixels wide —
                // and taken literally that is five and a half cups of
                // cornmeal. Wrong by 3.7x, in the direction that ruins the
                // dish, and it looks like a number somebody meant.
                //
                // Nobody writes an improper fraction in a recipe, so a
                // two-digit numerator over a common denominator, where the
                // second digit would make a proper fraction, is that lost
                // space and not a real quantity: "11/2" is 1½, "13/4" is 1¾.
                if whole.count == 2, [2.0, 3, 4, 8].contains(d),
                   let lead = whole.first.flatMap({ Double(String($0)) }),
                   let numer = whole.last.flatMap({ Double(String($0)) }),
                   numer < d {
                    value = lead + numer / d
                } else {
                    value /= d
                }
                idx = cursor
                found = true
            }
        } else if idx < line.endIndex, line[idx] == " ",
                  line.index(after: idx) < line.endIndex {
            // "1 1/2 cups" and "1 ½ cups" — a mixed number.
            let next = line.index(after: idx)
            if let f = fractions[line[next]] {
                value += f; found = true; idx = line.index(after: next)
            } else {
                var numer = ""
                var cursor = next
                while cursor < line.endIndex, isDigit(line[cursor]) {
                    numer.append(line[cursor]); cursor = line.index(after: cursor)
                }
                if !numer.isEmpty, cursor < line.endIndex, line[cursor] == "/" {
                    var denom = ""
                    var run = line.index(after: cursor)
                    while run < line.endIndex, isDigit(line[run]) {
                        denom.append(line[run]); run = line.index(after: run)
                    }
                    if let n = Double(numer), let d = Double(denom), d != 0 {
                        value += n / d; idx = run; found = true
                    }
                }
            }
        } else if idx < line.endIndex, let f = fractions[line[idx]] {
            value += f; found = true; idx = line.index(after: idx)
        }

        guard found else { return nil }
        return (value, String(line[idx...]).trimmingCharacters(in: .whitespaces))
    }

    // MARK: Aisle

    /// Which part of the shop sells it. The model does this well and the
    /// fallback used to not do it at all, so every heuristic import landed
    /// in "Other" and the grocery list lost its walking order — the one
    /// thing that makes the list worth generating.
    ///
    /// Longer phrases first: "tomato paste" is pantry, "tomato" is produce.
    private static let aisleKeywords: [(String, GroceryAisle)] = [
        ("chili powder", .pantry), ("chilli powder", .pantry), ("curry powder", .pantry),
        ("garlic powder", .pantry), ("onion powder", .pantry), ("cocoa powder", .pantry),
        ("salt and pepper", .pantry), ("black pepper", .pantry), ("white pepper", .pantry),
        ("peppercorn", .pantry), ("pepper flake", .pantry), ("cayenne", .pantry),
        ("sun-dried tomato", .pantry), ("tomato paste", .pantry), ("tomato sauce", .pantry),
        ("canned tomato", .pantry), ("coconut milk", .pantry), ("ice cream", .frozen),
        ("frozen", .frozen), ("sour cream", .dairy), ("cream cheese", .dairy),
        ("heavy cream", .dairy), ("olive oil", .pantry), ("soy sauce", .pantry),
        ("fish sauce", .pantry), ("peanut butter", .pantry), ("baking powder", .pantry),
        ("baking soda", .pantry), ("brown sugar", .pantry), ("bread crumb", .pantry),
        ("breadcrumb", .pantry), ("chicken stock", .pantry), ("chicken broth", .pantry),
        ("beef stock", .pantry), ("vegetable stock", .pantry), ("white wine", .beverages),
        ("red wine", .beverages),

        ("chicken", .meat), ("beef", .meat), ("pork", .meat), ("bacon", .meat),
        ("sausage", .meat), ("turkey", .meat), ("lamb", .meat), ("steak", .meat),
        ("shrimp", .meat), ("prawn", .meat), ("salmon", .meat), ("tuna", .meat),
        ("cod", .meat), ("fish", .meat), ("mince", .meat), ("ground ", .meat),

        ("milk", .dairy), ("cream", .dairy), ("butter", .dairy), ("cheese", .dairy),
        ("yogurt", .dairy), ("yoghurt", .dairy), ("egg", .dairy), ("parmesan", .dairy),
        ("mozzarella", .dairy), ("feta", .dairy), ("ricotta", .dairy),

        ("bread", .bakery), ("bun", .bakery), ("tortilla", .bakery), ("baguette", .bakery),
        ("pita", .bakery), ("brioche", .bakery),

        ("onion", .produce), ("garlic", .produce), ("tomato", .produce),
        ("lettuce", .produce), ("spinach", .produce), ("kale", .produce),
        ("carrot", .produce), ("celery", .produce), ("potato", .produce),
        ("lemon", .produce), ("lime", .produce), ("apple", .produce),
        ("banana", .produce), ("basil", .produce), ("cilantro", .produce),
        ("coriander", .produce), ("parsley", .produce), ("thyme", .produce),
        ("rosemary", .produce), ("mushroom", .produce), ("cucumber", .produce),
        ("avocado", .produce), ("ginger", .produce), ("scallion", .produce),
        ("green onion", .produce), ("zucchini", .produce), ("courgette", .produce),
        ("broccoli", .produce), ("berry", .produce), ("berries", .produce),
        ("orange", .produce), ("pepper", .produce), ("chilli", .produce),
        ("chili", .produce), ("shallot", .produce), ("leek", .produce),

        ("juice", .beverages), ("wine", .beverages), ("beer", .beverages),
        ("coffee", .beverages), ("tea", .beverages),

        ("flour", .pantry), ("sugar", .pantry), ("salt", .pantry),
        ("oil", .pantry), ("vinegar", .pantry), ("rice", .pantry),
        ("pasta", .pantry), ("spaghetti", .pantry), ("noodle", .pantry),
        ("bean", .pantry), ("lentil", .pantry), ("chickpea", .pantry),
        ("cumin", .pantry), ("paprika", .pantry), ("oregano", .pantry),
        ("cinnamon", .pantry), ("vanilla", .pantry), ("honey", .pantry),
        ("maple syrup", .pantry), ("cornstarch", .pantry), ("cornflour", .pantry),
        ("stock", .pantry), ("broth", .pantry), ("mustard", .pantry),
        ("mayonnaise", .pantry), ("ketchup", .pantry), ("nut", .pantry),
        ("chocolate", .pantry), ("yeast", .pantry), ("spice", .pantry),
    ]

    static func aisle(for name: String) -> GroceryAisle {
        let lower = name.lowercased()
        for (keyword, aisle) in aisleKeywords where lower.contains(keyword) { return aisle }
        return .other
    }

    // MARK: Facts

    /// "Prep: 10 min | Cook: 20 min | Serves 4" is three facts on one line,
    /// and reading it whole gave all three the same answer — the first
    /// number in the line. Cut it up before asking it anything.
    private static func factFragments(_ line: String) -> [String] {
        var parts = [line]
        for separator in ["|", "·", "•", "‧", "–", "—", "  "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The numbers written AFTER a keyword, which is where a fact's value
    /// actually lives. Taking the first number anywhere in the fragment read
    /// "Cook: 20 minutes" off the back of "Prep: 10 minutes".
    private static func numbers(in text: String, after keyword: String) -> [Int] {
        guard let range = text.range(of: keyword, options: .caseInsensitive) else { return [] }
        return text[range.upperBound...]
            .split(whereSeparator: { !isDigit($0) })
            .compactMap { Int($0) }
    }

    private static func allNumbers(_ text: String) -> [Int] {
        text.split(whereSeparator: { !isDigit($0) }).compactMap { Int($0) }
    }

    private static func servings(in fragment: String) -> Int? {
        let lower = fragment.lowercased()
        guard ["serves", "serving", "yield", "makes"].contains(where: { lower.contains($0) })
        else { return nil }
        for key in ["serves", "servings", "serving", "yields", "yield", "makes"] {
            if let n = numbers(in: fragment, after: key).first { return n }
        }
        // "4 servings" writes the number first.
        return allNumbers(fragment).first
    }

    private static func minutes(in fragment: String, keyed keys: [String]) -> Int? {
        let lower = fragment.lowercased()
        guard keys.contains(where: { lower.contains($0) }) else { return nil }
        guard lower.contains("min") || lower.contains("hour") || lower.contains("hr")
        else { return nil }
        var found: [Int] = []
        for key in keys where lower.contains(key) {
            found = numbers(in: fragment, after: key)
            if !found.isEmpty { break }
        }
        if found.isEmpty { found = allNumbers(fragment) }
        guard let first = found.first else { return nil }
        // "1 hour 10 minutes" is 70, not 1.
        if lower.contains("hour") || lower.contains("hr") {
            return first * 60 + (found.count > 1 ? found[1] : 0)
        }
        return first
    }
}
