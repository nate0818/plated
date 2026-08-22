import Foundation
import EventKit

/// Reads the user's Apple Calendar so the plan can show "you already have
/// something that night". Read-only, opt-in from the profile sheet, and
/// silent when access is off — the plan never nags about permissions.
@MainActor
@Observable
final class DayEventsProvider {
    static let shared = DayEventsProvider()

    private let store = EKEventStore()
    /// First event title per day-start, enough for a one-line cue.
    private(set) var titlesByDay: [Date: [String]] = [:]

    private init() {}

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Prompts for Calendar access (first time only) and loads on success.
    @discardableResult
    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        if granted { refresh() }
        return granted
    }

    /// Loads the next `days` of events. No-op without access.
    func refresh(days: Int = 42) {
        guard isAuthorized else { return }
        let start = Calendar.current.startOfDay(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        var grouped: [Date: [String]] = [:]
        for event in events {
            guard let title = event.title, !title.isEmpty else { continue }
            let day = Calendar.current.startOfDay(for: event.startDate)
            grouped[day, default: []].append(title)
        }
        titlesByDay = grouped
    }

    func firstEventTitle(on date: Date) -> String? {
        titlesByDay[date.startOfDay]?.first
    }

    func hasEvent(on date: Date) -> Bool {
        !(titlesByDay[date.startOfDay]?.isEmpty ?? true)
    }
}
