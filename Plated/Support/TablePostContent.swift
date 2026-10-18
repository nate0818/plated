import Foundation

/// Shared normalization and publication rules for a Table post. The existing
/// CloudKit fields carry general posts without treating restaurants as recipes.
struct TablePostContent {
    let title: String
    let caption: String
    let hasPhoto: Bool
    let choices: [String]
    let isRecipe: Bool

    init(title: String, caption: String, hasPhoto: Bool, choices: [String] = [],
         pendingChoice: String = "", isRecipe: Bool = false) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hasPhoto = hasPhoto
        self.isRecipe = isRecipe
        var normalized: [String] = []
        for value in choices + [pendingChoice] {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, normalized.count < 4,
                  !normalized.contains(where: { $0.localizedCaseInsensitiveCompare(clean) == .orderedSame }) else { continue }
            normalized.append(clean)
        }
        self.choices = normalized
    }

    var isValid: Bool {
        if !choices.isEmpty { return choices.count >= 2 && !caption.isEmpty }
        return hasPhoto || !title.isEmpty || !caption.isEmpty
    }

    var wireKind: String { !choices.isEmpty ? "ask" : (isRecipe ? "dish" : "post") }
}
