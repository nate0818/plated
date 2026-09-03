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

    /// How busy the day is, in a word, or nil when there is nothing on it.
    ///
    /// A count is the raw data, not the answer. "3 things on" makes a person
    /// do the arithmetic the app already did, and the arithmetic is the
    /// whole point: what somebody deciding dinner wants to know is whether
    /// they have an evening, not how many rows their calendar holds.
    ///
    /// The verdict is measured, not guessed: overlapping events are merged
    /// so a double-booked hour counts once, all-day entries are excluded
    /// because a birthday occupies no time, and only the waking part of the
    /// day is considered. It describes the calendar and nothing else. A
    /// quiet calendar is not a promise that the day is quiet.
    func load(on date: Date) -> String? {
        let all = events(on: date)
        guard !all.isEmpty else { return nil }

        let calendar = Calendar.current
        let timed = all.filter { !$0.isAllDay }
        guard !timed.isEmpty else {
            // Only all-day entries: something is marked on the day, but
            // none of it takes an hour away from cooking.
            return "Quiet day"
        }

        // Merge overlaps so a triple-booked hour is one hour.
        let day = calendar.startOfDay(for: date)
        let waking = (calendar.date(byAdding: .hour, value: 6, to: day) ?? day)
            ... (calendar.date(byAdding: .hour, value: 21, to: day) ?? day)
        var spans: [(Date, Date)] = []
        for event in timed.sorted(by: { $0.start < $1.start }) {
            let from = max(event.start, waking.lowerBound)
            let to = min(event.end, waking.upperBound)
            guard to > from else { continue }
            if let last = spans.last, from <= last.1 {
                spans[spans.count - 1].1 = max(last.1, to)
            } else {
                spans.append((from, to))
            }
        }
        let booked = spans.reduce(0.0) { $0 + $1.1.timeIntervalSince($1.0) } / 3600

        let verdict: String
        switch booked {
        case ..<2:  verdict = "Quiet day"
        case ..<5:  verdict = "Busy day"
        default:    verdict = "Packed day"
        }

        // The one clause that changes what gets cooked: when the day lets go.
        // Only while it still leaves an evening — a day running to ten is not
        // "clear after ten", it is just full.
        if let lastEnd = spans.last?.1 {
            let hour = calendar.component(.hour, from: lastEnd)
            if hour < 20, calendar.isDate(lastEnd, inSameDayAs: date) {
                let formatter = DateFormatter()
                formatter.dateFormat = calendar.component(.minute, from: lastEnd) == 0
                    ? "h a" : "h:mm a"
                return "\(verdict) · clear after \(formatter.string(from: lastEnd))"
            }
        }
        return verdict
    }
}
