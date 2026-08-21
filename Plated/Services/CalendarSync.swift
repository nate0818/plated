import Foundation
import EventKit

/// Mirrors gatherings into the user's calendar so a dinner party shows up
/// alongside everything else they are juggling that day.
@MainActor
final class CalendarSync {
    static let shared = CalendarSync()

    private let store = EKEventStore()

    enum SyncError: LocalizedError {
        case accessDenied
        case noWritableCalendar

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Plated needs Calendar access to add your gatherings. Enable it in Settings › Privacy › Calendars."
            case .noWritableCalendar:
                return "No writable calendar was found."
            }
        }
    }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    /// Creates or updates the calendar event backing a gathering.
    @discardableResult
    func sync(_ gathering: Gathering) async throws -> String {
        guard try await requestAccess() else { throw SyncError.accessDenied }

        let event: EKEvent
        if let id = gathering.calendarEventID, let existing = store.event(withIdentifier: id) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw SyncError.noWritableCalendar
            }
            event.calendar = calendar
        }

        event.title = gathering.title.isEmpty ? "Gathering" : gathering.title
        event.startDate = gathering.startDate
        event.endDate = gathering.endDate
        event.location = gathering.location.isEmpty ? nil : gathering.location
        event.notes = menuNotes(for: gathering)

        try store.save(event, span: .thisEvent, commit: true)
        gathering.calendarEventID = event.eventIdentifier
        return event.eventIdentifier
    }

    func removeEvent(for gathering: Gathering) async throws {
        guard let id = gathering.calendarEventID, let event = store.event(withIdentifier: id) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
        gathering.calendarEventID = nil
    }

    /// The menu, written into the event notes so guests-facing details travel
    /// with the calendar entry.
    private func menuNotes(for gathering: Gathering) -> String {
        var lines: [String] = []
        if !gathering.notes.isEmpty { lines.append(gathering.notes) }
        let menu = gathering.meals.map { "• \($0.title)" }
        if !menu.isEmpty {
            lines.append("")
            lines.append("Menu:")
            lines.append(contentsOf: menu)
        }
        if gathering.guestCount > 0 {
            lines.append("")
            lines.append("Cooking for \(gathering.guestCount).")
        }
        return lines.joined(separator: "\n")
    }
}
