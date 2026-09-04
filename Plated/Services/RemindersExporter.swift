import Foundation
import EventKit
import SwiftData

/// Pushes the grocery list into Apple Reminders so it is available on the Watch,
/// on a partner's phone, and at the store without opening Plated.
@MainActor
final class RemindersExporter {
    static let shared = RemindersExporter()

    private let store = EKEventStore()

    enum ExportError: LocalizedError {
        case accessDenied
        case noWritableList

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Plated needs Reminders access to send your grocery list. Enable it in Settings › Privacy › Reminders."
            case .noWritableList:
                return "No writable Reminders list was found."
            }
        }
    }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    /// Writes each unchecked item as a reminder. Items already exported (those
    /// carrying a `reminderID`) are updated in place instead of duplicated.
    @discardableResult
    func export(_ items: [GroceryItem], listName: String = "Groceries", quantities: [PersistentIdentifier: Double] = [:]) async throws -> Int {
        guard try await requestAccess() else { throw ExportError.accessDenied }

        let calendar = try remindersList(named: listName)
        var written = 0

        for item in items where !item.isChecked {
            let reminder: EKReminder
            if let id = item.reminderID,
               let existing = store.calendarItem(withIdentifier: id) as? EKReminder {
                reminder = existing
            } else {
                reminder = EKReminder(eventStore: store)
                reminder.calendar = calendar
            }

            reminder.title = [GroceryMeasure.shopping(quantities[item.persistentModelID] ?? item.quantity, item.unit).text, item.name].filter { !$0.isEmpty }.joined(separator: " ")
            reminder.notes = [item.aisleValue.rawValue, item.originTitle].filter { !$0.isEmpty }.joined(separator: "\n")

            try store.save(reminder, commit: false)
            item.reminderID = reminder.calendarItemIdentifier
            written += 1
        }

        try store.commit()
        return written
    }

    /// Finds the named Reminders list, falling back to the default list.
    private func remindersList(named name: String) throws -> EKCalendar {
        let lists = store.calendars(for: .reminder)
        if let match = lists.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        guard let fallback = store.defaultCalendarForNewReminders() ?? lists.first(where: { $0.allowsContentModifications }) else {
            throw ExportError.noWritableList
        }
        return fallback
    }
}
