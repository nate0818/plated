import Foundation

/// The quiet scorekeeper. Counts the moments worth counting — saves your
/// dishes earn from the table, kisses, firsts — so Home can show them off.
/// Local UserDefaults today; becomes server-side when the network arrives.
enum Awards {
    private static let savesKey = "awards.savesReceived"

    /// Someone plated a dish from `author`'s post into their cookbook.
    static func recordSaveReceived(by author: String) {
        var counts = UserDefaults.standard.dictionary(forKey: savesKey) as? [String: Int] ?? [:]
        counts[author, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: savesKey)
    }

    static func savesReceived(by author: String) -> Int {
        let counts = UserDefaults.standard.dictionary(forKey: savesKey) as? [String: Int] ?? [:]
        return counts[author] ?? 0
    }

    static var totalSavesRecorded: Int {
        let counts = UserDefaults.standard.dictionary(forKey: savesKey) as? [String: Int] ?? [:]
        return counts.values.reduce(0, +)
    }
}
