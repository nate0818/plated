import Foundation
import SwiftData

/// A larger event — holiday dinner, birthday, having friends over — that pulls
/// several planned meals under one heading and mirrors into the system calendar.
@Model
final class Gathering {
    var title: String = ""
    var notes: String = ""
    var startDate: Date = Date.now
    var endDate: Date = Date.now.addingTimeInterval(3 * 3600)
    var guestCount: Int = 0
    var location: String = ""
    /// EventKit identifier once mirrored to the user's calendar, so we update
    /// rather than duplicate on subsequent syncs.
    var calendarEventID: String?

    @Relationship(deleteRule: .nullify, inverse: \PlannedMeal.gathering)
    var plannedMeals: [PlannedMeal]? = []

    init(
        title: String = "",
        notes: String = "",
        startDate: Date = .now,
        endDate: Date? = nil,
        guestCount: Int = 0,
        location: String = ""
    ) {
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate ?? startDate.addingTimeInterval(3 * 3600)
        self.guestCount = guestCount
        self.location = location
    }

    var meals: [PlannedMeal] {
        (plannedMeals ?? []).sorted { $0.slotValue.sortOrder < $1.slotValue.sortOrder }
    }

    var isSyncedToCalendar: Bool { calendarEventID != nil }
}
