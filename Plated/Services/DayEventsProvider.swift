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
    struct DayEvent {
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
    }

    /// Every event on each day, not just its name.
    ///
    /// This used to be titles only, and the day page named the first one it
    /// happened to find and called that "the calendar". On a day with six
    /// things on it that is one arbitrary title standing in for the whole
    /// day, which is not a fact about the day. What a person deciding what
    /// to cook actually wants to know is how much is on and when they are
    /// free, so the day keeps its times.
    private(set) var eventsByDay: [Date: [DayEvent]] = [:]

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

        var grouped: [Date: [DayEvent]] = [:]
        for event in events {
            guard let title = event.title, !title.isEmpty else { continue }
            let day = Calendar.current.startOfDay(for: event.startDate)
            grouped[day, default: []].append(DayEvent(
                title: title,
                start: event.startDate,
                end: event.endDate ?? event.startDate,
                isAllDay: event.isAllDay
            ))
        }
        eventsByDay = grouped
    }

    func events(on date: Date) -> [DayEvent] {
        eventsByDay[date.startOfDay] ?? []
    }

    func hasEvent(on date: Date) -> Bool {
        !events(on: date).isEmpty
    }

    /// How busy the day is, in one line, or nil when there is nothing on it.
    ///
    /// The count is the whole day; the second clause is the only part that
    /// bears on dinner, so it is only offered when it is true and useful.
    /// "Clear after" is the end of the last thing scheduled, which is a fact
    /// about the calendar rather than a claim about the person: they may
    /// well be busy with something the calendar has never heard of.
    ///
    /// All-day entries count toward how full the day looks but never toward
    /// when it frees up, because a birthday does not occupy an evening.
    func load(on date: Date) -> String? {
        let all = events(on: date)
        guard !all.isEmpty else { return nil }

        var parts = [all.count.things("thing") + " on"]

        let timed = all.filter { !$0.isAllDay }
        if let lastEnd = timed.map(\.end).max() {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: lastEnd)
            // Only worth saying while it still leaves an evening. A day that
            // runs to ten o'clock is not "clear after ten", it is just full.
            if hour < 20, calendar.isDate(lastEnd, inSameDayAs: date) {
                let formatter = DateFormatter()
                formatter.dateFormat = calendar.component(.minute, from: lastEnd) == 0
                    ? "h a" : "h:mm a"
                parts.append("clear after \(formatter.string(from: lastEnd))")
            }
        }
        return parts.joined(separator: " · ")
    }
}
