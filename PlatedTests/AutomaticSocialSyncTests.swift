import XCTest
import CloudKit
@testable import Plated

@MainActor
final class AutomaticSocialSyncTests: XCTestCase {
    func testVisibleSessionPullsImmediatelyAndAgainWithoutRefreshAndStopsInBackground() async {
        let firstSleep = expectation(description: "first automatic read finished")
        let secondSleep = expectation(description: "second automatic read finished")
        var reads = 0
        var sleeper: CheckedContinuation<Void, Error>?
        let sync = ForegroundSync(
            pull: { reads += 1 }, succeeded: { true }, engaged: { true },
            sleep: { seconds in
                XCTAssertEqual(seconds, 5)
                try await withCheckedThrowingContinuation { continuation in
                    sleeper = continuation
                    if reads == 1 { firstSleep.fulfill() }
                    if reads == 2 { secondSleep.fulfill() }
                }
            }
        )
        sync.setActive(true)
        await fulfillment(of: [firstSleep], timeout: 2)
        sync.setActive(true)
        XCTAssertEqual(reads, 1, "repeated active signals must not start a second reader")
        sleeper?.resume()
        sleeper = nil
        await fulfillment(of: [secondSleep], timeout: 2)
        sync.setActive(false)
        sleeper?.resume(throwing: CancellationError())
        sleeper = nil
        await Task.yield()
        XCTAssertEqual(reads, 2)
    }

    func testStoppingDuringAnUncancellableReadDoesNotScheduleMoreWork() async {
        let started = expectation(description: "read started")
        var pendingRead: CheckedContinuation<Void, Never>?
        var sleeps = 0
        let sync = ForegroundSync(
            pull: {
                await withCheckedContinuation { continuation in
                    pendingRead = continuation
                    started.fulfill()
                }
            }, succeeded: { true }, engaged: { true },
            sleep: { _ in sleeps += 1; throw CancellationError() }
        )
        sync.setActive(true)
        await fulfillment(of: [started], timeout: 2)
        sync.setActive(false)
        pendingRead?.resume()
        await Task.yield()
        XCTAssertEqual(sleeps, 0)
    }

    func testNetworkFailureBacksOffAndSuccessRestoresTheVisibleCadence() {
        XCTAssertEqual(ForegroundSync.delay(engaged: true, failures: 0), 5)
        XCTAssertEqual(ForegroundSync.delay(engaged: true, failures: 1), 10)
        XCTAssertEqual(ForegroundSync.delay(engaged: true, failures: 2), 20)
        XCTAssertEqual(ForegroundSync.delay(engaged: true, failures: 100), 60)
        XCTAssertEqual(ForegroundSync.delay(engaged: false, failures: 0), 15)
    }

    func testBackgroundDeadlineDoesNotWaitForCloudKitAndCompletesOnlyOnce() async {
        let deadline = expectation(description: "OS callback before stalled read finishes")
        var results: [Bool] = []
        let reply = BackgroundFetchCompletion(seconds: 0.01) { success in
            results.append(success)
            deadline.fulfill()
        }
        await fulfillment(of: [deadline], timeout: 2)
        XCTAssertEqual(results, [false])
        reply.finish(true)
        reply.finish(false)
        XCTAssertEqual(results, [false])
    }

    func testBackgroundSuccessWinsOverItsDeadline() async {
        let duplicate = expectation(description: "no duplicate callback")
        duplicate.isInverted = true
        var results: [Bool] = []
        let reply = BackgroundFetchCompletion(seconds: 0.01) { success in
            results.append(success)
            if results.count > 1 { duplicate.fulfill() }
        }
        reply.finish(true)
        await fulfillment(of: [duplicate], timeout: 0.05)
        XCTAssertEqual(results, [true])
    }

    func testOnlyExpiredOrDeletedZonesResetTheirCursor() {
        for code in [CKError.Code.networkUnavailable, .networkFailure, .serviceUnavailable,
                     .requestRateLimited, .notAuthenticated, .permissionFailure] {
            XCTAssertFalse(TableShare.shouldResetCursor(after: CKError(code)))
        }
        for code in [CKError.Code.changeTokenExpired, .zoneNotFound, .userDeletedZone] {
            XCTAssertTrue(TableShare.shouldResetCursor(after: CKError(code)))
        }
    }

    func testQueuedCommentSurvivesMoreThanTwentyFailuresAndANewEditRetriesImmediately() {
        let queue = TableOutbox.shared
        queue.clear()
        defer { queue.clear() }
        let work = TableOutbox.Work.note(post: "dish", zoneOwner: "owner", id: "comment")
        let first = queue.enqueue(work, author: "author")
        for _ in 0..<25 { queue.failed(first.id) }
        XCTAssertEqual(queue.pending.count, 1, "offline comments must never silently disappear")
        XCTAssertFalse(queue.pending[0].isReady())
        XCTAssertTrue(queue.pending[0].isReady(at: .now.addingTimeInterval(301)))
        let edited = queue.enqueue(work, author: "author")
        XCTAssertTrue(edited.isReady())
        XCTAssertEqual(edited.tries, 0)
        queue.finish(first, succeeded: true)
        XCTAssertEqual(queue.pending, [edited], "an old completion cannot delete a new edit")
    }

    func testExistingOutboxEntriesDecodeWithoutARetryDate() throws {
        let json = #"{"id":"plate:p","work":{"plate":{"post":"p","zoneOwner":"o","active":true}},"author":"a","at":0,"tries":2}"#
        let entry = try JSONDecoder().decode(TableOutbox.Entry.self, from: Data(json.utf8))
        XCTAssertTrue(entry.isReady())
        XCTAssertEqual(entry.tries, 2)
    }

    func testDeviceRegistrationCacheIsScopedToAccountAndAPNsEnvironment() {
        let production = Directory.registrationBinding(session: "first-session", sandbox: false)
        XCTAssertNotEqual(production, Directory.registrationBinding(session: "second-session", sandbox: false))
        XCTAssertNotEqual(production, Directory.registrationBinding(session: "first-session", sandbox: true))
        XCTAssertEqual(production, Directory.registrationBinding(session: "first-session", sandbox: false))
        XCTAssertFalse(production.contains("first-session"))
    }
}
