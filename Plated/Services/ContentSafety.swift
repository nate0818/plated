import CryptoKit
import Foundation
import Observation

/// Local safety controls for the private Table.
///
/// CloudKit is the transport for Table content, not a moderation backend, so
/// blocking is deliberately a private choice on this device. A
/// blocked author is never notified and their records are not edited. Reports
/// open a pre-addressed email with opaque record references; post text,
/// comments and photos never enter the report URL.
@MainActor
@Observable
final class ContentSafety {
    static let shared = ContentSafety()

    struct Author: Equatable, Hashable {
        let identity: String
        let displayName: String

        init(identity: String, displayName: String) {
            self.identity = identity.trimmingCharacters(in: .whitespacesAndNewlines)
            self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var label: String { displayName.isEmpty ? "this person" : displayName }
        var firstName: String {
            displayName.split(separator: " ").first.map(String.init) ?? "this person"
        }

        /// Identity is authoritative whenever the record carries it. Exact,
        /// normalized names are migration glue for old records only.
        fileprivate var storageKey: String? {
            if !identity.isEmpty { return "id:\(identity)" }
            let name = ContentSafety.normalized(displayName)
            return name.isEmpty ? nil : "legacy-name:\(name)"
        }
    }

    struct BlockedAuthor: Codable, Equatable, Identifiable {
        let id: String
        let displayName: String
        let blockedAt: Date
    }

    enum ReportReason: String, CaseIterable, Identifiable {
        case harassment = "Bullying or harassment"
        case hate = "Hate or discrimination"
        case unsafe = "Unsafe or inappropriate"
        case spam = "Spam or misleading"
        case other = "Something else"

        var id: String { rawValue }
    }

    struct ReportTarget: Equatable {
        enum Kind: String { case post, comment }

        let kind: Kind
        let contentReference: String
        let author: Author
        let zoneOwner: String

        init(
            kind: Kind,
            recordName: String,
            authorID: String,
            authorName: String,
            zoneOwner: String = "",
            createdAt: Date
        ) {
            self.kind = kind
            self.author = Author(identity: authorID, displayName: authorName)
            self.zoneOwner = zoneOwner.trimmingCharacters(in: .whitespacesAndNewlines)
            let record = recordName.trimmingCharacters(in: .whitespacesAndNewlines)
            if record.isEmpty {
                // A local legacy row may not have a wire name. Keep its name
                // out of the report while still producing a useful reference.
                let seed = "\(kind.rawValue)|\(authorID)|\(createdAt.timeIntervalSince1970)"
                self.contentReference = "local-\(ContentSafety.fingerprint(seed))"
            } else {
                self.contentReference = record
            }
        }

        static func post(_ post: TablePost) -> ReportTarget {
            ReportTarget(
                kind: .post,
                recordName: post.shareRecordName,
                authorID: post.authorID,
                authorName: post.authorName,
                zoneOwner: post.shareZoneOwner,
                createdAt: post.createdAt
            )
        }

        static func comment(_ comment: TableComment, on post: TablePost) -> ReportTarget {
            ReportTarget(
                kind: .comment,
                recordName: comment.shareRecordName,
                authorID: comment.authorID,
                authorName: comment.authorName,
                zoneOwner: post.shareZoneOwner,
                createdAt: comment.createdAt
            )
        }
    }

    static let supportAddress = "privacy@getplated.food"
    private static let blockedKey = "plated.contentSafety.blockedAuthors.v1"
    private static let reportSaltKey = "plated.contentSafety.reportSalt.v1"

    private let defaults: UserDefaults
    private let reportSalt: String
    private(set) var blockedAuthors: [BlockedAuthor] = []

    init(defaults: UserDefaults? = nil) {
        let resolvedDefaults = defaults
            ?? UserDefaults(suiteName: WidgetBridge.appGroupID)
            ?? .standard
        self.defaults = resolvedDefaults
        if let savedSalt = resolvedDefaults.string(forKey: Self.reportSaltKey), !savedSalt.isEmpty {
            self.reportSalt = savedSalt
        } else {
            let newSalt = UUID().uuidString
            self.reportSalt = newSalt
            resolvedDefaults.set(newSalt, forKey: Self.reportSaltKey)
        }
        load()
    }

    func isBlocked(authorID: String, authorName: String) -> Bool {
        let author = Author(identity: authorID, displayName: authorName)
        if !author.identity.isEmpty {
            return blockedAuthors.contains { $0.id == "id:\(author.identity)" }
        }

        let legacyName = Self.normalized(author.displayName)
        guard !legacyName.isEmpty else { return false }
        // A block created from a modern row retains the person's display
        // name so their exact-name legacy rows disappear too. Never use a
        // name to match a modern row carrying somebody else's stable id.
        return blockedAuthors.contains {
            Self.normalized($0.displayName) == legacyName
        }
    }

    func canBlock(
        _ author: Author,
        currentIdentityIDs: [String],
        currentDisplayNames: [String]
    ) -> Bool {
        guard author.storageKey != nil else { return false }
        return !Self.isSelf(
            author,
            currentIdentityIDs: currentIdentityIDs,
            currentDisplayNames: currentDisplayNames
        )
    }

    /// Reporting and blocking deliberately have different eligibility.
    /// A legacy row can be reportable even when its missing identity makes
    /// Block too ambiguous (for example, two people called Sam). The caller
    /// still withholds Report where its local model proves legacy ownership.
    func canReport(
        _ author: Author,
        currentIdentityIDs: [String],
        knownToBeSelf: Bool
    ) -> Bool {
        guard !knownToBeSelf else { return false }
        if !author.identity.isEmpty {
            let ownIDs = Set(currentIdentityIDs.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty })
            return !ownIDs.contains(author.identity)
        }
        // With no stable identity, absence of proof is not proof of self.
        // The caller can withhold Report when its model has local ownership
        // evidence; all other legacy/blank authors remain reportable.
        return true
    }

    /// Table-scoped activity from a blocked author follows the same local
    /// lens as their post/comment. Household planning and roster events do
    /// not: blocking somebody at the Table cannot hide shared-plan changes.
    func hidesTableActivity(_ notification: PlatedNotification) -> Bool {
        switch notification.kindValue {
        case .plateReaction, .commentReaction, .saveReceived, .commentAdded, .askPosted, .dishPosted, .voteCast:
            return isBlocked(authorID: notification.actorID, authorName: notification.actorName)
        default:
            return false
        }
    }

    func hidesTableNotice(kind: String, authorID: String, authorName: String) -> Bool {
        guard ["dish", "ask", "comment", "plates", "kiss", "votes"].contains(kind) else {
            return false
        }
        return isBlocked(authorID: authorID, authorName: authorName)
    }

    @discardableResult
    func block(
        _ author: Author,
        currentIdentityIDs: [String],
        currentDisplayNames: [String]
    ) -> Bool {
        guard canBlock(
            author,
            currentIdentityIDs: currentIdentityIDs,
            currentDisplayNames: currentDisplayNames
        ), let key = author.storageKey else { return false }

        guard !blockedAuthors.contains(where: { $0.id == key }) else { return false }
        blockedAuthors.append(BlockedAuthor(
            id: key,
            displayName: author.displayName.isEmpty ? "Someone at your Table" : author.displayName,
            blockedAt: .now
        ))
        blockedAuthors.sort {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        save()
        return true
    }

    func unblock(_ blocked: BlockedAuthor) {
        guard blockedAuthors.contains(where: { $0.id == blocked.id }) else { return }
        blockedAuthors.removeAll { $0.id == blocked.id }
        save()
    }

    /// A mailto is intentionally assembled from references only. There is no
    /// parameter for content text or image data, which makes accidentally
    /// leaking either impossible at this boundary.
    func reportURL(for target: ReportTarget, reason: ReportReason) -> URL? {
        let authorReference = target.author.identity.isEmpty
            ? "legacy-\(Self.fingerprint(reportSalt + "|" + Self.normalized(target.author.displayName)))"
            : target.author.identity
        let reportReference = Self.fingerprint([
            target.kind.rawValue,
            target.contentReference,
            authorReference,
            target.zoneOwner,
        ].joined(separator: "|"))

        var lines = [
            "Reason: \(reason.rawValue)",
            "Content type: \(target.kind.rawValue)",
            "Content reference: \(target.contentReference)",
            "Author reference: \(authorReference)",
        ]
        if !target.zoneOwner.isEmpty {
            lines.append("Table reference: \(target.zoneOwner)")
        }
        lines += [
            "Report reference: \(reportReference)",
            "",
            "Please add any context that would help us review this report. Do not attach private photos unless support asks for them.",
        ]

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.supportAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Plated Table report \(reportReference)"),
            URLQueryItem(name: "body", value: lines.joined(separator: "\n")),
        ]
        return components.url
    }

    /// For focused tests and account-boundary cleanup.
    func reset() {
        blockedAuthors = []
        defaults.removeObject(forKey: Self.blockedKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.blockedKey),
              let saved = try? JSONDecoder().decode([BlockedAuthor].self, from: data)
        else { return }
        blockedAuthors = saved
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(blockedAuthors) else { return }
        defaults.set(data, forKey: Self.blockedKey)
        SocialPush.requestSync()
    }

    private static func isSelf(
        _ author: Author,
        currentIdentityIDs: [String],
        currentDisplayNames: [String]
    ) -> Bool {
        if !author.identity.isEmpty {
            return Set(currentIdentityIDs.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }).contains(author.identity)
        }

        // Legacy rows do not carry identity. Err toward withholding Block
        // when either the exact name or first name could be this person;
        // hiding a stranger called Sam is less harmful than letting someone
        // block their own old posts and lose the unblock context.
        let target = normalized(author.displayName)
        let targetFirst = firstName(target)
        guard !target.isEmpty else { return true }
        for ownName in currentDisplayNames {
            let own = normalized(ownName)
            if own == target || firstName(own) == targetFirst { return true }
        }
        return false
    }

    nonisolated private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func firstName(_ normalizedName: String) -> String {
        normalizedName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? normalizedName
    }

    nonisolated private static func fingerprint(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
