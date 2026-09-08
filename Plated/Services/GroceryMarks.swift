import CryptoKit
import Foundation
import Observation
import SwiftData

/// Check-offs and dismissals on the grocery list (docs/household.md §3.5).
///
/// Auto lines are regenerated from the shared plan on every phone, and each
/// phone mints its own rows, so a row can never travel: whichever phone
/// rebuilt second would delete the other's. What travels is the human-owned
/// fact, keyed on `GroceryMeasure.key(name, unit)`, the way a plate does: a
/// timestamped value, last writer wins, never a monotonic merge. A max can
/// never carry an uncheck.
///
/// Deliberately not SwiftData, for the reason `TableLedger` is not: the
/// zone is the one authority and the mirror would be a second writer.
@MainActor
@Observable
final class GroceryMarks {
    static let shared = GroceryMarks()

    struct Mark: Codable, Equatable {
        var lineKey: String
        /// `[shoppingID: quantity]`. An empty map means unchecked and is a
        /// value, never a missing key.
        var purchases: [String: Double]
        /// yyyy-MM-dd of the last day of the window the line was dismissed
        /// in, so a dismissal expires with the window as it does today.
        var dismissedUntil: String?
        var at: Date
        var by: String
    }

    /// Keyed on `lineKey`.
    private var marks: [String: Mark] = [:]

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: "grocery-marks.json")
    }

    private init() { load() }

    // MARK: Reading

    func mark(for lineKey: String) -> Mark? { marks[lineKey] }

    /// Every mark, for `publishAll` and the tests.
    var all: [Mark] { marks.values.sorted { $0.lineKey < $1.lineKey } }

    var isEmpty: Bool { marks.isEmpty }

    /// A raw key has spaces and can exceed a record name, so the wire name
    /// is a hash of it. The full key still travels on the record.
    static func recordName(for lineKey: String) -> String {
        let digest = SHA256.hash(data: Data(lineKey.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "mark-" + String(hex.prefix(32))
    }

    // MARK: Writing

    /// A check-off or a dismissal made on this phone. Always written as now,
    /// by me: the person's tap is the newest fact about the line, whatever
    /// the book held before.
    func record(lineKey: String, purchases: [String: Double], dismissedUntil: String?) {
        guard !lineKey.isEmpty else { return }
        let now = Date.now
        marks[lineKey] = Mark(
            lineKey: lineKey, purchases: purchases, dismissedUntil: dismissedUntil,
            at: now, by: TableIdentity.cached
        )
        save()
        // Only once there is a household to send it to, the way the save
        // observer gates on membership. A solo phone has no zone, so every
        // queued mark answers `.retry` forever, is never counted as a try,
        // and is paid for again on every launch, foreground and pull. The
        // book still holds the mark, and `publishAll` enqueues the whole
        // book the moment the household starts sharing.
        guard HouseholdShare.membership != .solo else { return }
        HouseholdOutbox.shared.enqueueUpsert(.mark, Self.recordName(for: lineKey), at: now)
    }

    /// The same purchases under a different shopping id, after a duplicate
    /// night lost a merge. Nobody touched the line, so the mark keeps its
    /// own `at` and `by`: recording it as now, by me, would make this phone
    /// the newest writer of a line it never checked off, and that answer
    /// would then beat a real check-off made on another phone a moment ago.
    func rewrite(lineKey: String, purchases: [String: Double]) {
        guard let existing = marks[lineKey] else { return }
        marks[lineKey] = Mark(
            lineKey: lineKey, purchases: purchases, dismissedUntil: existing.dismissedUntil,
            at: existing.at, by: existing.by
        )
        save()
        guard HouseholdShare.membership != .solo else { return }
        HouseholdOutbox.shared.enqueueUpsert(.mark, Self.recordName(for: lineKey), at: existing.at)
    }

    /// A mark from the wire. Applied only when it is newer than what this
    /// phone holds, and then whole: purchases and dismissal are one value,
    /// because a check on one phone and an uncheck on another are two
    /// answers to one question, not two halves of an answer.
    ///
    /// Also applied to the live `GroceryItem` with the same key, so a
    /// check-off from another phone appears while the sheet is open rather
    /// than on the next rebuild. The row is changed, not saved: the merge
    /// that folds a page of marks saves once at the end.
    @discardableResult
    func fold(_ mark: Mark, into context: ModelContext) -> Bool {
        if let local = marks[mark.lineKey], local.at >= mark.at { return false }
        marks[mark.lineKey] = mark
        save()
        print("PLATED HOUSEHOLD: folded mark for \(mark.lineKey) by \(mark.by)")

        // The sheet holds every non-manual row, past windows included, so
        // the fetch is not filtered by window; the dismissal rule below is
        // what decides which windows the mark reaches.
        let rows = (try? context.fetch(FetchDescriptor<GroceryItem>(
            predicate: #Predicate { !$0.isManual }
        ))) ?? []
        for item in rows where item.lineKey == mark.lineKey {
            Self.apply(mark, to: item)
        }
        return true
    }

    /// One place that turns a mark into row state, so the builder and the
    /// fold cannot disagree about what a mark means.
    static func apply(_ mark: Mark, to item: GroceryItem) {
        item.purchases = mark.purchases
        item.isChecked = item.sources.isEmpty ? !mark.purchases.isEmpty : item.isPurchased()
        item.isDismissed = Self.isDismissed(mark, windowStart: item.weekStart)
    }

    /// The dismissal covers every window that starts on or before its last
    /// day, and lapses with the first window that starts after it.
    static func isDismissed(_ mark: Mark, windowStart: Date) -> Bool {
        guard let until = mark.dismissedUntil else { return false }
        return until >= HouseholdMember.day(windowStart)
    }

    /// A placeholder identity became a real one. Marks written offline were
    /// attributed to `local-…`; it is the same person.
    func reattribute(from old: String, to new: String) {
        guard old != new else { return }
        for (key, mark) in marks where mark.by == old {
            marks[key]?.by = new
        }
        save()
    }

    func clear() {
        marks = [:]
        save()
    }

    // MARK: Disk

    private func load() {
        guard let url = Self.url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Mark].self, from: data) else { return }
        marks = decoded
    }

    private func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(marks) else { return }
        // Atomic: a force-quit mid-tap must not leave a half-written book,
        // which would decode as nothing and uncheck the whole list.
        try? data.write(to: url, options: .atomic)
    }
}
