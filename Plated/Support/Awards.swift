import Foundation

/// The quiet scorekeeper. Counts the moments worth counting — saves your
/// dishes earn from the table, kisses, firsts — so Home can show them off.
/// Local UserDefaults today; becomes server-side when the network arrives.
enum Awards {
    private static let savesKey = "awards.savesReceived"

    /// "Sam Meadows" the author and "Sam" the comment name are the same
    /// person — first name, lowercased, is the ledger key until real user
    /// IDs exist. Known trade-off: two people who share a first name share
    /// a ledger line; real IDs (the network) dissolve this.
    private static func normalize(_ name: String) -> String {
        name.split(separator: " ").first.map { $0.lowercased() } ?? name.lowercased()
    }

    /// Counts recorded before normalization existed were keyed by full
    /// name; fold them into their normalized keys once so nobody's earned
    /// saves read as zero after an update.
    private static func rekeyIfNeeded() {
        let flag = "awards.rekeyed.v1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        let counts = UserDefaults.standard.dictionary(forKey: savesKey) as? [String: Int] ?? [:]
        guard !counts.isEmpty else { return }
        var folded: [String: Int] = [:]
        for (key, value) in counts {
            folded[normalize(key), default: 0] += value
        }
        UserDefaults.standard.set(folded, forKey: savesKey)
    }

    /// Someone plated a dish from `author`'s post into their cookbook.
    static func recordSaveReceived(by author: String) {
        rekeyIfNeeded()
        var counts = UserDefaults.standard.dictionary(forKey: savesKey) as? [String: Int] ?? [:]
        counts[normalize(author), default: 0] += 1
        UserDefaults.standard.set(counts, forKey: savesKey)
    }

    static func savesReceived(by author: String) -> Int {
        rekeyIfNeeded()
        let counts = UserDefaults.standard.dictionary(forKey: savesKey) as? [String: Int] ?? [:]
        return counts[normalize(author)] ?? 0
    }

    static var totalSavesRecorded: Int {
        let counts = UserDefaults.standard.dictionary(forKey: savesKey) as? [String: Int] ?? [:]
        return counts.values.reduce(0, +)
    }
}
