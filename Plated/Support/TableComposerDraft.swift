import Foundation

/// One atomic local file includes the photograph as well as the written draft.
struct TableComposerDraft: Codable, Equatable {
    var title: String
    var caption: String
    var kind: String
    var poll: [String]
    var pollEntry: String
    var tags: [String]
    var destination: String?
    var photo: Data?

    static func url(for key: String, directory: URL? = nil) throws -> URL {
        let root = try directory ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TableDrafts", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let safe = Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return root.appendingPathComponent(safe + ".json")
    }
    func save(to url: URL) throws { try JSONEncoder().encode(self).write(to: url, options: .atomic) }
    static func load(from url: URL) throws -> Self { try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)) }
}
