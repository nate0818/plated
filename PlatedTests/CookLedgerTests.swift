import XCTest
@testable import Plated

final class CookLedgerTests: XCTestCase {
    func testOlderCookingSessionWithoutTimerPreferencesStillDecodes() throws {
        let data = Data(#"{"startedAt":1791417600,"lastTouched":1791417660,"step":0,"stepCount":3,"timerEndsAt":1791418200,"timerStep":0}"#.utf8)

        let session = try JSONDecoder().decode(CookLedger.Session.self, from: data)

        XCTAssertNil(session.timerDuration)
        XCTAssertNil(session.timerMuted)
    }

    func testTimerDurationAndMutePreferenceSurviveEncoding() throws {
        let data = Data(#"{"startedAt":1791417600,"lastTouched":1791417660,"step":0,"stepCount":3,"timerEndsAt":1791418200,"timerStep":0,"timerDuration":600,"timerMuted":true}"#.utf8)

        let session = try JSONDecoder().decode(CookLedger.Session.self, from: data)
        let roundTrip = try JSONDecoder().decode(CookLedger.Session.self, from: JSONEncoder().encode(session))

        XCTAssertEqual(roundTrip.timerDuration, 600)
        XCTAssertEqual(roundTrip.timerMuted, true)
    }
    func testExplicitTimerPauseSurvivesRelaunchAndDoesNotConsumePausedTime() throws {
        let data = Data(#"{"startedAt":0,"lastTouched":0,"step":0,"stepCount":0,"timerEndsAt":600,"timerStep":0,"timerDuration":600}"#.utf8)
        var session = try JSONDecoder().decode(CookLedger.Session.self, from: data)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        session.pauseTimer(at: start.addingTimeInterval(120))
        XCTAssertEqual(session.timerPausedRemaining, 480)
        session.pauseTimer(at: start.addingTimeInterval(240))
        XCTAssertEqual(session.timerPausedRemaining, 480, "Repeated pause must not shorten the frozen timer")
        session.checkedIngredients = [0, 2]
        var restored = try JSONDecoder().decode(CookLedger.Session.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.checkedIngredients, [0, 2])
        restored.resumeTimer(at: start.addingTimeInterval(1200))
        XCTAssertEqual(restored.timerEndsAt, start.addingTimeInterval(1680))
        XCTAssertNil(restored.timerPausedRemaining)
        restored.resumeTimer(at: start.addingTimeInterval(1300))
        XCTAssertEqual(restored.timerEndsAt, start.addingTimeInterval(1680), "Repeated resume must not extend time")
    }
    func testExpiredTimerCannotBePausedIntoAnActiveTimer() throws {
        let data = Data(#"{"startedAt":0,"lastTouched":0,"step":0,"stepCount":0,"timerEndsAt":60,"timerStep":0}"#.utf8)
        var session = try JSONDecoder().decode(CookLedger.Session.self, from: data)
        session.pauseTimer(at: Date(timeIntervalSinceReferenceDate: 61))
        XCTAssertNil(session.timerPausedRemaining)
    }

    @MainActor
    func testPauseWaitsForDelayedAlarmAddBeforeResumeSchedulesReplacement() async {
        let queue = NotificationOperationQueue()
        var pendingAlarm: String?
        var releaseAdd: CheckedContinuation<Void, Never>?
        let add = queue.enqueue {
            await withCheckedContinuation { releaseAdd = $0 }
            pendingAlarm = "old"
        }
        while releaseAdd == nil { await Task.yield() }
        let pause = queue.enqueue { pendingAlarm = nil }
        let resume = queue.enqueue { pendingAlarm = "resumed" }
        releaseAdd?.resume()
        await add.value; await pause.value; await resume.value
        XCTAssertEqual(pendingAlarm, "resumed", "A delayed old add/cancel cannot replace or remove the resumed alarm")
        await queue.enqueue { pendingAlarm = nil }.value
        XCTAssertNil(pendingAlarm)
    }

}
