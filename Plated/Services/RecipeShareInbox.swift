import Foundation

/// The handoff point between the iOS Share extension and the main app.
///
/// The extension cannot touch SwiftData and the app may not be running, so it
/// leaves one small Codable parcel in the existing app group. Consuming is a
/// move, not a read: a shared note must open the importer once, not on every
/// foreground transition until somebody saves it.
enum RecipeShareInbox {
    static let appGroupID = "group.com.natemeadows.plated"
    static let payloadKey = "pending-recipe-import"

    struct Payload: Codable {
        var text: String
        var imageNames: [String]
        var createdAt: Date
    }

    struct Import {
        var text: String
        var images: [Data]
        /// The exact preferences value that produced this import. A second
        /// share may replace the inbox while the first importer is animating
        /// on screen; acknowledgements must never delete that newer parcel.
        fileprivate var receipt: Data
        fileprivate var imageNames: [String]
    }

    /// Read without removing. The main app acknowledges only after the
    /// importer owns the payload; another sheet may already be on screen
    /// when the share extension wakes it.
    static func peek() -> Import? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: payloadKey) else { return nil }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            // A payload from an interrupted or incompatible extension must not
            // poison every future foreground check.
            defaults.removeObject(forKey: payloadKey)
            return nil
        }
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )
        let images = payload.imageNames.compactMap { name -> Data? in
            guard let url = container?.appending(path: name) else { return nil }
            return try? Data(contentsOf: url)
        }
        let value = Import(
            text: payload.text,
            images: images,
            receipt: data,
            imageNames: payload.imageNames
        )
        guard !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else {
            // A syntactically valid parcel can still be unusable after iOS
            // purges its temporary image files. Clear only this exact one so
            // it cannot poison every future foreground check.
            acknowledge(value)
            return nil
        }
        return value
    }

    /// Remove only the parcel that was actually handed to the importer.
    /// Returns false when a newer share has replaced it and must stay queued.
    @discardableResult
    static func acknowledge(_ value: Import) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              defaults.data(forKey: payloadKey) == value.receipt
        else { return false }
        defaults.removeObject(forKey: payloadKey)
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )
        for name in value.imageNames {
            guard let url = container?.appending(path: name) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
        return true
    }

    /// Kept for callers that truly want an atomic move.
    static func consume() -> Import? {
        guard let value = peek() else { return nil }
        acknowledge(value)
        return value
    }
}
