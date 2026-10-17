import XCTest
import EventKit
import SwiftData
@testable import Plated

/// Opt-in: isolated model store and uniquely marked, temporary Calendar events.
/// Calls production CalendarSync against EventKit and removes only its own events.
@MainActor
final class CalendarIntegrationTests: XCTestCase {
    private func requireAccess() async throws {
        guard ProcessInfo.processInfo.arguments.contains("-plated-calendar-integration") else {
            throw XCTSkip("Run explicitly during Calendar release verification")
        }
        let granted = try await EKEventStore().requestFullAccessToEvents()
        XCTAssertTrue(granted)
        XCTAssertEqual(EKEventStore.authorizationStatus(for: .event), .fullAccess)
    }

    func testDeniedRemovalPreservesReferenceForRetry() async throws {
        guard ProcessInfo.processInfo.arguments.contains("-plated-calendar-denied") else {
            throw XCTSkip("Run explicitly with Calendar access denied on the isolated simulator")
        }
        XCTAssertEqual(EKEventStore.authorizationStatus(for: .event), .denied)
        let gathering = Gathering(title: "Plated release denied-access check")
        gathering.calendarEventID = "unreadable-while-access-is-denied"
        do {
            try await CalendarSync.shared.removeEvent(for: gathering)
            XCTFail("Lack of permission must not be treated as a successful removal")
        } catch CalendarSync.SyncError.accessDenied {
            XCTAssertEqual(gathering.calendarEventID, "unreadable-while-access-is-denied")
        }
    }

    func testRemovingAnExternallyDeletedEventClearsItsLocalReference() async throws {
        try await requireAccess()
        let gathering = Gathering(title: "Plated release check " + UUID().uuidString)
        let id = try await CalendarSync.shared.sync(gathering)
        let reader = EKEventStore()
        let event = try XCTUnwrap(reader.event(withIdentifier: id))
        try reader.remove(event, span: .thisEvent, commit: true)
        try await CalendarSync.shared.removeEvent(for: gathering)
        XCTAssertNil(gathering.calendarEventID)
        XCTAssertFalse(gathering.isSyncedToCalendar)
    }

    func testMovedCalendarAndDaylightSavingTimeEditsRetainOneEvent() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Additional disposable calendars are confined to the isolated simulator")
        #else
        try await requireAccess()
        let store = EKEventStore()
        let originalCalendar = try XCTUnwrap(store.defaultCalendarForNewEvents)
        let temporary = EKCalendar(for: .event, eventStore: store)
        temporary.title = "Plated release calendar " + UUID().uuidString
        temporary.source = originalCalendar.source
        try store.saveCalendar(temporary, commit: true)
        defer { try? store.removeCalendar(temporary, commit: true) }

        let marker = "Plated release check " + UUID().uuidString
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: "2026-11-01T05:30:00Z"))
        let gathering = Gathering(title: marker, startDate: start, guestCount: 3)
        defer {
            let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-86400),
                end: start.addingTimeInterval(86400 * 3), calendars: nil)
            for event in store.events(matching: predicate) where event.title == marker {
                try? store.remove(event, span: .thisEvent, commit: true)
            }
        }
        let firstID = try await CalendarSync.shared.sync(gathering)
        store.reset()
        let moved = try XCTUnwrap(store.event(withIdentifier: firstID))
        moved.calendar = temporary
        try store.save(moved, span: .thisEvent, commit: true)

        gathering.startDate = try XCTUnwrap(formatter.date(from: "2026-11-02T23:15:00Z"))
        gathering.endDate = gathering.startDate.addingTimeInterval(90 * 60)
        let editedID = try await CalendarSync.shared.sync(gathering)
        store.reset()
        let edited = try XCTUnwrap(store.event(withIdentifier: editedID))
        XCTAssertEqual(edited.calendar.calendarIdentifier, temporary.calendarIdentifier,
            "Editing a gathering must preserve the calendar selected in Apple Calendar")
        XCTAssertEqual(edited.startDate, gathering.startDate)
        XCTAssertEqual(edited.endDate, gathering.endDate)
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-86400),
            end: start.addingTimeInterval(86400 * 3), calendars: nil)
        XCTAssertEqual(store.events(matching: predicate).filter { $0.title == marker }.count, 1)
        try await CalendarSync.shared.removeEvent(for: gathering)
        #endif
    }

    func testEventKitCreateUpdateRecreateAndRemove() async throws {
        guard ProcessInfo.processInfo.arguments.contains("-plated-calendar-integration") else {
            throw XCTSkip("Run explicitly during Calendar release verification")
        }
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            print("PLATED RELEASE: waiting for Calendar permission for temporary verification events")
            let granted = try await EKEventStore().requestFullAccessToEvents()
            XCTAssertTrue(granted)
        }
        XCTAssertEqual(EKEventStore.authorizationStatus(for: .event), .fullAccess)
        let container = try ModelContainer(for: PlatedStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        let marker = "Plated release check " + UUID().uuidString
        let start = Calendar.current.date(bySettingHour: 18, minute: 15, second: 0, of: Date())!
        let gathering = Gathering(title: marker, notes: "Test menu only", startDate: start,
                                  guestCount: 5, location: "Isolated simulator")
        let meal = PlannedMeal(date: start, customTitle: "Release-test pasta")
        context.insert(gathering); context.insert(meal); meal.gathering = gathering
        try context.save()
        let reader = EKEventStore()
        defer {
            let predicate = reader.predicateForEvents(withStart: start.addingTimeInterval(-86400),
                                                      end: start.addingTimeInterval(86400), calendars: nil)
            for event in reader.events(matching: predicate) where event.title.hasPrefix(marker) {
                try? reader.remove(event, span: .thisEvent, commit: true)
            }
        }
        let firstID = try await CalendarSync.shared.sync(gathering)
        try context.save()
        reader.reset()
        let created = try XCTUnwrap(reader.event(withIdentifier: firstID))
        XCTAssertEqual(created.title, marker)
        XCTAssertEqual(created.startDate, start)
        XCTAssertEqual(created.endDate, start.addingTimeInterval(3 * 3600))
        XCTAssertEqual(created.location, "Isolated simulator")
        XCTAssertTrue(created.notes?.contains("Release-test pasta") == true)
        XCTAssertTrue(created.notes?.contains("Cooking for 5.") == true)

        gathering.title += " updated"; gathering.location = ""; gathering.guestCount = 7
        let updatedID = try await CalendarSync.shared.sync(gathering)
        XCTAssertEqual(updatedID, firstID, "A retry must update, not duplicate")
        reader.reset()
        let updated = try XCTUnwrap(reader.event(withIdentifier: updatedID))
        XCTAssertEqual(updated.title, gathering.title)
        XCTAssertTrue(updated.location?.isEmpty ?? true)
        XCTAssertTrue(updated.notes?.contains("Cooking for 7.") == true)
        let predicate = reader.predicateForEvents(withStart: start.addingTimeInterval(-86400),
                                                  end: start.addingTimeInterval(86400), calendars: nil)
        XCTAssertEqual(reader.events(matching: predicate).filter { $0.title.hasPrefix(marker) }.count, 1)

        // The person deletes the Calendar event, then asks Plated to sync again.
        try reader.remove(updated, span: .thisEvent, commit: true)
        let recreatedID = try await CalendarSync.shared.sync(gathering)
        reader.reset()
        XCTAssertNotNil(reader.event(withIdentifier: recreatedID))
        try await CalendarSync.shared.removeEvent(for: gathering)
        XCTAssertNil(gathering.calendarEventID)
        reader.reset()
        XCTAssertNil(reader.event(withIdentifier: recreatedID))
        try await CalendarSync.shared.removeEvent(for: gathering)
    }
}
