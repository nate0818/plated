import Foundation

extension Calendar {
    /// Start of the week containing `date`, honoring the user's first weekday.
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }

    /// The seven day-start dates of the week containing `date`.
    func weekDays(for date: Date) -> [Date] {
        let start = startOfWeek(for: date)
        return (0..<7).compactMap { self.date(byAdding: .day, value: $0, to: start) }
    }

    func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        isDate(lhs, inSameDayAs: rhs)
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func formattedWeekday() -> String {
        formatted(.dateTime.weekday(.abbreviated))
    }

    func formattedDayNumber() -> String {
        formatted(.dateTime.day())
    }
}
