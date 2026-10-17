import XCTest
import WidgetKit

/// Compiles the widget extension's actual source into this harness.
final class WidgetTimelineTests: XCTestCase {
    func testMidnightUsesCalendarDaysAcrossDaylightSavingChanges() throws {
        let original = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        defer { NSTimeZone.default = original }
        let iso = ISO8601DateFormatter()
        for (start, end, hours) in [
            ("2026-03-08T05:00:00Z", "2026-03-09T04:00:00Z", 23.0),
            ("2026-11-01T04:00:00Z", "2026-11-02T05:00:00Z", 25.0)
        ] {
            let now = try XCTUnwrap(iso.date(from: start))
            let expectedMidnight = try XCTUnwrap(iso.date(from: end))
            var snapshot = WeekSnapshot.sample
            snapshot.generatedAt = now
            let loaded = WeekSnapshot.Loaded(snapshot: snapshot, dishPhoto: nil,
                dishPhotoDark: nil, tablePhoto: nil, cookbookPhoto: nil)
            let timeline = WeekProvider.timeline(from: loaded, now: now)
            XCTAssertEqual(timeline.entries.last?.date, expectedMidnight)
            XCTAssertEqual(expectedMidnight.timeIntervalSince(now), hours * 3600)
            XCTAssertNotNil(timeline.entries.first?.snapshot?.tonight)
            XCTAssertNil(timeline.entries.last?.snapshot?.tonight)
            XCTAssertNil(timeline.entries.last?.snapshot?.grocery)
        }
    }

    func testTimeZoneChangeExpiresAFormerlyCurrentDinner() throws {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        let iso = ISO8601DateFormatter()
        let generated = try XCTUnwrap(iso.date(from: "2026-10-17T08:00:00Z"))
        let now = try XCTUnwrap(iso.date(from: "2026-10-18T06:00:00Z"))
        var snapshot = WeekSnapshot.sample
        snapshot.generatedAt = generated
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertTrue(snapshot.isCurrent(on: now))
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertFalse(snapshot.isCurrent(on: now))
        let loaded = snapshot.aged(dishPhoto: nil, dishPhotoDark: nil, tablePhoto: nil, now: now)
        XCTAssertNil(loaded.snapshot.tonight)
        XCTAssertNil(loaded.snapshot.grocery)
        XCTAssertNotNil(loaded.snapshot.table)
        XCTAssertNotNil(loaded.snapshot.cookbook)
    }

    func testMidnightEntryExpiresDinnerGroceriesAndPhotoWithoutProviderRefresh() throws {
        var snapshot = WeekSnapshot.sample
        let now = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date())!
        snapshot.generatedAt = now
        let photo = UIImage(systemName: "fork.knife")!
        let loaded = WeekSnapshot.Loaded(snapshot: snapshot, dishPhoto: photo,
            dishPhotoDark: photo, tablePhoto: photo, cookbookPhoto: photo)
        let timeline = WeekProvider.timeline(from: loaded, now: now)
        XCTAssertEqual(timeline.entries.count, 2)
        let first = timeline.entries[0], midnight = timeline.entries[1]
        XCTAssertNotNil(first.snapshot?.tonight)
        XCTAssertNotNil(first.snapshot?.grocery)
        XCTAssertTrue(first.snapshot?.isCurrent(on: first.date) == true)
        XCTAssertEqual(midnight.date, Calendar.current.startOfDay(for: now.addingTimeInterval(86400)))
        XCTAssertNil(midnight.snapshot?.tonight)
        XCTAssertNil(midnight.snapshot?.grocery)
        XCTAssertNil(midnight.photo); XCTAssertNil(midnight.photoDark)
        XCTAssertFalse(midnight.snapshot?.isCurrent(on: midnight.date) == true)
        XCTAssertEqual(midnight.snapshot?.table?.dishTitle, snapshot.table?.dishTitle)
        XCTAssertNotNil(midnight.cookbookPhoto)
    }
    func testMissingSnapshotStaysUnknownAcrossMidnight() {
        let timeline = WeekProvider.timeline(from: nil, now: Date())
        XCTAssertEqual(timeline.entries.count, 2)
        XCTAssertTrue(timeline.entries.allSatisfy { $0.snapshot == nil })
    }
    func testWeekOldSnapshotDropsPlanButRetainsDurableCards() {
        var snapshot = WeekSnapshot.sample
        snapshot.generatedAt = Calendar.current.date(byAdding: .day, value: -8, to: Date())!
        let loaded = snapshot.aged(dishPhoto: nil, dishPhotoDark: nil, tablePhoto: nil)
        XCTAssertEqual(loaded.snapshot.days.count, 7)
        XCTAssertFalse(loaded.snapshot.days.contains(where: \.planned))
        XCTAssertNil(loaded.snapshot.grocery); XCTAssertNil(loaded.snapshot.tonight)
        XCTAssertNotNil(loaded.snapshot.table); XCTAssertNotNil(loaded.snapshot.cookbook)
    }
    func testWidgetItemURLsPreserveOpaqueIDs() throws {
        let id = "recipe:a+b/c?d&é"
        let url = PlatedLink.item("recipe", id: id, fallback: PlatedLink.cookbook)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "recipe")
        XCTAssertEqual(components.queryItems?.first?.value, id)
        XCTAssertEqual(PlatedLink.item("recipe", id: nil, fallback: PlatedLink.cookbook), PlatedLink.cookbook)
    }
}
