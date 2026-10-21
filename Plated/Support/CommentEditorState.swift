import Foundation

/// Selection-aware mention editing. UTF-16 ranges cross the native text-input
/// boundary; invalid/stale ranges are rejected rather than indexing a new string.
enum CommentMentionInsertion {
    struct Result: Equatable {
        var text: String
        var caretUTF16: Int
    }

    static func activeToken(in text: String, selection: NSRange?, names: [String] = []) -> NSRange? {
        let selected = selection ?? NSRange(location: text.utf16.count, length: 0)
        guard selected.length == 0, let range = validRange(selected, in: text) else { return nil }
        // Display names can contain spaces. A multiword query is active only
        // while it is a prefix of an actual picker name, not the prose after
        // an already-completed mention.
        if let at = text[..<range.lowerBound].lastIndex(of: "@"),
           at == text.startIndex || (!isQueryCharacter(text[text.index(before: at)]) && text[text.index(before: at)] != "@") {
            let nameStart = text.index(after: at)
            let query = String(text[nameStart..<range.lowerBound])
            let candidates = names.filter { $0.contains(" ") && $0.lowercased().hasPrefix(query.lowercased()) }
            if !query.isEmpty, !candidates.isEmpty {
                var end = range.lowerBound
                // Consume the rest of the word containing the caret. A caret
                // just after a space has not entered the following word yet.
                if end > nameStart, isQueryCharacter(text[text.index(before: end)]) {
                    while end < text.endIndex, isQueryCharacter(text[end]) {
                        end = text.index(after: end)
                    }
                }
                let consumed = text[nameStart..<end].split(separator: " ").map { $0.lowercased() }
                var wordCount = consumed.count
                var matching = candidates.map { $0.lowercased().split(separator: " ").map(String.init) }.filter { words in
                    consumed.count <= words.count && zip(consumed, words).allSatisfy { typed, expected in
                        typed.hasPrefix(expected) || expected.hasPrefix(typed)
                    }
                }
                // Cross whitespace only for a whole following token that is
                // equal to, a prefix of, or starts with the next name word.
                // Meadowsworth/Mea match Meadows; unrelated with/maybe do not.
                while !matching.isEmpty, end < text.endIndex {
                    var nextStart = end
                    while nextStart < text.endIndex, text[nextStart] == " " {
                        nextStart = text.index(after: nextStart)
                    }
                    let alreadyAfterSpace = end > nameStart && text[text.index(before: end)] == " "
                    guard (nextStart > end || alreadyAfterSpace), nextStart < text.endIndex,
                          isQueryCharacter(text[nextStart]) else { break }
                    var nextEnd = nextStart
                    while nextEnd < text.endIndex, isQueryCharacter(text[nextEnd]) {
                        nextEnd = text.index(after: nextEnd)
                    }
                    let word = text[nextStart..<nextEnd].lowercased()
                    let continued = matching.filter { words in
                        wordCount < words.count && (word.hasPrefix(words[wordCount]) || words[wordCount].hasPrefix(word))
                    }
                    guard !continued.isEmpty else { break }
                    matching = continued
                    wordCount += 1
                    end = nextEnd
                }
                return NSRange(at..<end, in: text)
            }
        }
        var start = range.lowerBound
        while start > text.startIndex {
            let previous = text.index(before: start)
            let character = text[previous]
            if character == "@" {
                if previous > text.startIndex {
                    let beforeAt = text[text.index(before: previous)]
                    // An email address or another @ is not a mention token.
                    guard !isQueryCharacter(beforeAt), beforeAt != "@" else { return nil }
                }
                var end = range.upperBound
                while end < text.endIndex, isQueryCharacter(text[end]) {
                    end = text.index(after: end)
                }
                return NSRange(previous..<end, in: text)
            }
            guard isQueryCharacter(character) else { return nil }
            start = previous
        }
        return nil
    }

    static func inserting(_ name: String, into text: String, selection: NSRange?) -> Result? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let selected = selection ?? NSRange(location: text.utf16.count, length: 0)
        guard validRange(selected, in: text) != nil,
              var range = validRange(activeToken(in: text, selection: selected, names: [name]) ?? selected, in: text) else { return nil }
        let previous = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
        let needsSpace = previous.map { !$0.isWhitespace && !"([{\"“".contains($0) } ?? false
        // Reuse a following ordinary space, preserving newlines and the rest
        // of the sentence. The resulting caret is after one useful separator.
        if range.upperBound < text.endIndex, text[range.upperBound] == " " {
            range = range.lowerBound..<text.index(after: range.upperBound)
        }
        let replacement = (needsSpace ? " " : "") + "@" + name + " "
        let prefixLength = text[..<range.lowerBound].utf16.count
        var result = text
        result.replaceSubrange(range, with: replacement)
        return Result(text: result, caretUTF16: prefixLength + replacement.utf16.count)
    }

    /// Notification recipients are complete, explicit mentions, never name
    /// substrings or the domain portion of an email. A longer display name
    /// consumes its whole span so @Samantha cannot also mention Sam.
    static func mentionedNames(in text: String, names: [String]) -> [String] {
        let candidates = names.enumerated().filter { !$0.element.isEmpty }.sorted {
            if $0.element.count != $1.element.count { return $0.element.count > $1.element.count }
            return $0.offset < $1.offset
        }.map(\.element)
        var found: [String] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            defer { if cursor < text.endIndex { cursor = text.index(after: cursor) } }
            guard text[cursor] == "@" else { continue }
            if cursor > text.startIndex {
                let previous = text[text.index(before: cursor)]
                guard !isQueryCharacter(previous), previous != "@" else { continue }
            }
            let nameStart = text.index(after: cursor)
            for name in candidates {
                guard text[nameStart...].hasPrefix(name) else { continue }
                let end = text.index(nameStart, offsetBy: name.count)
                guard end == text.endIndex || (!isQueryCharacter(text[end]) && text[end] != "@") else { continue }
                if !found.contains(name) { found.append(name) }
                // The outer loop advances once. Preserve a following @ for
                // boundary handling, and skip every character inside the name.
                cursor = text.index(before: end)
                break
            }
        }
        return found
    }

    /// Foundation can represent a UTF-16 offset inside a surrogate pair or
    /// an extended grapheme cluster. Only indices obtained from this String's
    /// Character boundaries are safe for the traversal and replacement above.
    static func validRange(_ selection: NSRange, in text: String) -> Range<String.Index>? {
        let length = text.utf16.count
        guard selection.location >= 0, selection.length >= 0,
              selection.location <= length, selection.length <= length - selection.location else { return nil }
        let endOffset = selection.location + selection.length
        func boundary(at offset: Int) -> String.Index? {
            if offset == length { return text.endIndex }
            return text.indices.first { $0.utf16Offset(in: text) == offset }
        }
        guard let start = boundary(at: selection.location), let end = boundary(at: endOffset) else { return nil }
        return start..<end
    }

    private static func isQueryCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
            || character == "-" || character == "'" || character == "’"
    }
}

/// A private reply draft belongs to its writing account and exact destination.
/// Legacy unscoped drafts remain untouched; their author cannot be established.
enum CommentReplyDraftStore {
    struct Scope: Codable, Equatable {
        let account: String
        let zoneOwner: String
        let postID: String

        init(account: String, zoneOwner: String, postID: String) {
            self.account = account
            self.zoneOwner = zoneOwner.isEmpty ? account : zoneOwner
            self.postID = postID
        }

        var key: String {
            "table.replyDraft.v2." + [account, zoneOwner, postID]
                .map { Data($0.utf8).base64EncodedString() }.joined(separator: ".")
        }

        func belongs(to currentAccount: String) -> Bool {
            !account.isEmpty && account == currentAccount
        }
    }

    struct Draft: Codable, Equatable {
        var text: String = ""
        var link: String = ""
        var replyTo: String?
        var parent: String?
        var photo: Data?

        var isEmpty: Bool { text.isEmpty && link.isEmpty && photo == nil }
        var showsLink: Bool { !link.isEmpty }
        var showsAttachments: Bool { showsLink || photo != nil }
    }

    private struct Envelope: Codable {
        var scope: Scope
        var draft: Draft
    }

    static func load(scope: Scope, defaults: UserDefaults = .standard) -> Draft? {
        guard let data = defaults.data(forKey: scope.key),
              let saved = try? JSONDecoder().decode(Envelope.self, from: data),
              saved.scope == scope else { return nil }
        return saved.draft
    }

    @discardableResult
    static func save(_ draft: Draft, scope: Scope, currentAccount: String,
                     defaults: UserDefaults = .standard) -> Bool {
        guard scope.belongs(to: currentAccount) else { return false }
        if draft.isEmpty {
            remove(scope: scope, defaults: defaults)
        } else {
            guard let data = try? JSONEncoder().encode(Envelope(scope: scope, draft: draft)) else { return false }
            defaults.set(data, forKey: scope.key)
        }
        return true
    }

    static func remove(scope: Scope, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: scope.key)
    }
}

/// A photo result can update only the selection and draft that requested it.
/// Sending/removing/switching accounts invalidates the request before the next
/// composer can receive a late completion, even when the same asset is picked.
struct CommentPhotoLoadState {
    struct Request: Equatable {
        fileprivate let id: UUID
        fileprivate let scope: CommentReplyDraftStore.Scope
    }

    private var current: Request?

    mutating func begin(scope: CommentReplyDraftStore.Scope) -> Request {
        let request = Request(id: UUID(), scope: scope)
        current = request
        return request
    }

    mutating func invalidate() { current = nil }

    func accepts(_ request: Request, scope: CommentReplyDraftStore.Scope,
                 currentAccount: String, selectionMatches: Bool) -> Bool {
        current == request && request.scope == scope
            && scope.belongs(to: currentAccount) && selectionMatches
    }
}
