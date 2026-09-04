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
    }

    static func consume() -> Import? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: payloadKey) else { return nil }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            // A payload from an interrupted or incompatible extension must not
            // poison every future foreground check.
            defaults.removeObject(forKey: payloadKey)
            return nil
        }
        defaults.removeObject(forKey: payloadKey)

        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )
        let images = payload.imageNames.compactMap { name -> Data? in
            guard let url = container?.appending(path: name) else { return nil }
            defer { try? FileManager.default.removeItem(at: url) }
            return try? Data(contentsOf: url)
        }
        guard !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else {
            return nil
        }
        return Import(text: payload.text, images: images)
    }
}
