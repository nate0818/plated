import XCTest
import Observation
import Network
@testable import Plated

@MainActor
final class TablePostPublicationTests: XCTestCase {
    private func key(_ account: String = "account-a", _ owner: String = "table-a", _ record: String = "post-a") -> TablePostPublication.Key {
        .init(account: account, owner: owner, recordName: record)
    }

    func testIdleAttemptFailureRetryAndAcknowledgedPublication() {
        let ledger = TablePostPublication()
        let post = key()
        XCTAssertEqual(ledger.status(for: post, isPublished: false), .saved)
        let first = ledger.begin(post)
        XCTAssertEqual(ledger.status(for: post, isPublished: false), .sending)
        ledger.finish(first, succeeded: false)
        XCTAssertEqual(ledger.status(for: post, isPublished: false), .failed)
        let retry = ledger.begin(post)
        XCTAssertEqual(ledger.status(for: post, isPublished: false), .sending)
        ledger.finish(retry, succeeded: true)
        XCTAssertEqual(ledger.status(for: post, isPublished: true), .shared)
    }

    func testFailureCannotStopAnotherConcurrentAttempt() {
        let ledger = TablePostPublication()
        let post = key()
        let composer = ledger.begin(post)
        let backlog = ledger.begin(post)
        ledger.finish(composer, succeeded: false)
        XCTAssertEqual(ledger.status(for: post, isPublished: false), .sending)
        ledger.finish(backlog, succeeded: true)
        XCTAssertEqual(ledger.status(for: post, isPublished: true), .shared)
    }

    func testLateFailureCannotEraseSuccessfulConcurrentPublication() {
        let ledger = TablePostPublication()
        let post = key()
        let composer = ledger.begin(post)
        let backlog = ledger.begin(post)
        ledger.finish(composer, succeeded: true)
        XCTAssertEqual(ledger.status(for: post, isPublished: true), .sending)
        ledger.finish(backlog, succeeded: false)
        XCTAssertEqual(ledger.status(for: post, isPublished: true), .shared)
    }

    func testAllOverlappingFailuresRemainSendingUntilLastAttemptEnds() {
        let ledger = TablePostPublication()
        let post = key()
        let first = ledger.begin(post)
        let second = ledger.begin(post)
        ledger.finish(second, succeeded: false)
        XCTAssertEqual(ledger.status(for: post, isPublished: false), .sending)
        ledger.finish(first, succeeded: false)
        XCTAssertEqual(ledger.status(for: post, isPublished: false), .failed)
    }

    func testDuplicateCompletionCannotFailOrFinishNewRetry() {
        let ledger = TablePostPublication()
        let post = key()
        let old = ledger.begin(post)
        ledger.finish(old, succeeded: false)
        let retry = ledger.begin(post)
        ledger.finish(old, succeeded: false)
        XCTAssertEqual(ledger.status(for: post, isPublished: false), .sending)
        ledger.finish(retry, succeeded: true)
        XCTAssertEqual(ledger.status(for: post, isPublished: true), .shared)
    }

    func testAccountDestinationAndRecordAreIndependentScopes() {
        let ledger = TablePostPublication()
        let first = ledger.begin(key())
        XCTAssertEqual(ledger.status(for: key("account-b"), isPublished: false), .saved)
        XCTAssertEqual(ledger.status(for: key("account-a", "table-b"), isPublished: false), .saved)
        XCTAssertEqual(ledger.status(for: key("account-a", "table-a", "post-b"), isPublished: false), .saved)
        ledger.finish(first, succeeded: false)
        XCTAssertEqual(ledger.status(for: key(), isPublished: false), .failed)
        XCTAssertEqual(ledger.status(for: key("account-b"), isPublished: false), .saved)
    }

    func testAccountResetInvalidatesOldAttemptCompletion() {
        let ledger = TablePostPublication()
        let old = ledger.begin(key())
        ledger.clear()
        let current = ledger.begin(key("account-b"))
        ledger.finish(old, succeeded: false)
        XCTAssertEqual(ledger.status(for: key(), isPublished: false), .saved)
        XCTAssertEqual(ledger.status(for: key("account-b"), isPublished: false), .sending)
        ledger.finish(current, succeeded: true)
        XCTAssertEqual(ledger.status(for: key("account-b"), isPublished: true), .shared)
    }

    func testDestinationResolutionMovesOnlyItsOwnAttempt() {
        let ledger = TablePostPublication()
        let unassigned = key("local-a", "")
        let resolved = key("account-a", "table-a")
        let first = ledger.begin(unassigned)
        let other = ledger.begin(unassigned)
        ledger.move(first, to: resolved)
        XCTAssertEqual(ledger.status(for: unassigned, isPublished: false), .sending)
        XCTAssertEqual(ledger.status(for: resolved, isPublished: false), .sending)
        ledger.finish(first, succeeded: false)
        XCTAssertEqual(ledger.status(for: resolved, isPublished: false), .failed)
        XCTAssertEqual(ledger.status(for: unassigned, isPublished: false), .sending)
        ledger.finish(other, succeeded: false)
    }

    func testLegacyOwnZoneCanonicalizationDoesNotAssignAnUnchosenAudience() {
        XCTAssertEqual(TablePostPublication.Key(account: "a", owner: "", recordName: "p", isPublished: true),
                       TablePostPublication.Key(account: "a", owner: "a", recordName: "p"))
        XCTAssertNotEqual(TablePostPublication.Key(account: "a", owner: "", recordName: "p"),
                          TablePostPublication.Key(account: "a", owner: "a", recordName: "p"))
    }

    func testOnlyPlaceholderResolutionOrSameConfirmedAccountCanContinue() {
        XCTAssertTrue(TablePostPublication.mayContinue(from: "local-a", as: "account-a"))
        XCTAssertTrue(TablePostPublication.mayContinue(from: "account-a", as: "account-a"))
        XCTAssertFalse(TablePostPublication.mayContinue(from: "account-a", as: "account-b"))
        XCTAssertFalse(TablePostPublication.mayContinue(from: "account-a", as: "local-a"))
        XCTAssertFalse(TablePostPublication.mayContinue(from: "local-a", as: ""))
    }

    func testPublicationAcceptsOnlyTheExactResolvingPlaceholder() {
        XCTAssertTrue(TablePostPublication.mayPublish(authorID: "local-this-device",
            initialAccount: "local-this-device", confirmedAccount: "account-a"))
        XCTAssertTrue(TablePostPublication.mayPublish(authorID: "account-a",
            initialAccount: "local-this-device", confirmedAccount: "account-a"),
            "The exact placeholder may already have been migrated before preflight")
        XCTAssertFalse(TablePostPublication.mayPublish(authorID: "local-another-device",
            initialAccount: "local-this-device", confirmedAccount: "account-a"),
            "An unrelated pending author cannot be adopted just because its ID is local")
    }

    func testConfirmedAccountCannotAdoptUnrelatedOfflineOrRealAuthors() {
        XCTAssertFalse(TablePostPublication.mayPublish(authorID: "local-old-account",
            initialAccount: "account-a", confirmedAccount: "account-a"))
        XCTAssertFalse(TablePostPublication.mayPublish(authorID: "account-b",
            initialAccount: "account-a", confirmedAccount: "account-a"))
        XCTAssertFalse(TablePostPublication.mayPublish(authorID: "account-b",
            initialAccount: "account-a", confirmedAccount: "account-b"),
            "Even a row matching the new account cannot continue an old-account attempt")
    }

    func testOwnConfirmedEchoAndLegacyAuthorRemainPublishable() {
        XCTAssertTrue(TablePostPublication.mayPublish(authorID: "account-a",
            initialAccount: "account-a", confirmedAccount: "account-a"),
            "A published own record echoed through a shared zone still belongs to its confirmed author")
        XCTAssertTrue(TablePostPublication.mayPublish(authorID: "",
            initialAccount: "account-a", confirmedAccount: "account-a"))
        XCTAssertTrue(TablePostPublication.mayPublish(authorID: "",
            initialAccount: "local-this-device", confirmedAccount: "account-a"))
    }

    func testUnconfirmedIdentityCannotPublishEvenItsMatchingAuthor() {
        XCTAssertFalse(TablePostPublication.mayPublish(authorID: "local-this-device",
            initialAccount: "local-this-device", confirmedAccount: "local-this-device"))
        XCTAssertFalse(TablePostPublication.mayPublish(authorID: "",
            initialAccount: "local-this-device", confirmedAccount: ""))
    }

    func testPublishedTruthSurvivesLedgerRelaunchAndFailedEdit() {
        let ledger = TablePostPublication()
        XCTAssertEqual(ledger.status(for: key(), isPublished: true), .shared)
        let edit = ledger.begin(key())
        ledger.finish(edit, succeeded: false)
        XCTAssertEqual(ledger.status(for: key(), isPublished: true), .shared)
        ledger.clear()
        XCTAssertEqual(ledger.status(for: key(), isPublished: true), .shared)
        XCTAssertEqual(ledger.status(for: key(), isPublished: false), .saved)
    }

    func testStatusObservesBackgroundAttemptWithoutFeedRefresh() async {
        let ledger = TablePostPublication()
        let post = key()
        let changed = expectation(description: "observable publication status changed")
        withObservationTracking {
            _ = ledger.status(for: post, isPublished: false)
        } onChange: { changed.fulfill() }
        _ = ledger.begin(post)
        await fulfillment(of: [changed], timeout: 1)
    }

    func testStatusCopyDoesNotClaimDeliveryOrReads() {
        XCTAssertEqual(TablePostPublication.Status.saved.label, "Saved on this device · not shared yet")
        XCTAssertEqual(TablePostPublication.Status.shared.label, "Shared with your Table")
        XCTAssertEqual(TablePostPublication.Status.waitingForConnection.label, "Waiting for connection · Your post is saved")
        for status in [TablePostPublication.Status.saved, .waitingForConnection, .sending, .failed, .shared] {
            XCTAssertFalse(status.label.lowercased().contains("delivered"))
            XCTAssertFalse(status.label.lowercased().contains("read"))
        }
    }

    func testOnlyAnObservedUnsatisfiedPathMeansOffline() {
        XCTAssertEqual(NetworkAvailability.classify(.satisfied), .available)
        XCTAssertEqual(NetworkAvailability.classify(.unsatisfied), .unavailable)
        XCTAssertEqual(NetworkAvailability.classify(.requiresConnection), .unknown)
        let ledger = TablePostPublication()
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .unknown), .saved)
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .available), .saved)
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .unavailable), .waitingForConnection)
    }

    func testGenericFailureDoesNotInferAnOfflineConnection() {
        let ledger = TablePostPublication()
        ledger.finish(ledger.begin(key()), succeeded: false)
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .unknown), .failed)
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .available), .failed)
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .unavailable), .waitingForConnection)
        // Removing the outage doesn't erase the failed attempt or invent success.
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .available), .failed)
    }

    func testInFlightAndAcknowledgedPublicationKeepPriorityDuringAnOutage() {
        let ledger = TablePostPublication()
        let attempt = ledger.begin(key())
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .unavailable), .sending)
        ledger.finish(attempt, succeeded: true)
        XCTAssertEqual(ledger.status(for: key(), isPublished: true, connection: .unavailable), .shared)
        let failedEdit = ledger.begin(key())
        ledger.finish(failedEdit, succeeded: false)
        XCTAssertEqual(ledger.status(for: key(), isPublished: true, connection: .unavailable), .shared)
    }

    func testRecoveredPathRequiresARealAttemptAndReceiptBeforeShared() {
        let ledger = TablePostPublication()
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .unavailable), .waitingForConnection)
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .available), .saved)
        let recovered = ledger.begin(key())
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .available), .sending)
        ledger.finish(recovered, succeeded: true)
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .available), .saved)
        XCTAssertEqual(ledger.status(for: key(), isPublished: true, connection: .available), .shared)
    }

    func testOutageDoesNotMergeAccountDestinationOrRecordAttempts() {
        let ledger = TablePostPublication()
        let first = ledger.begin(key())
        let unrelated = [key("account-b"), key("account-a", "table-b"), key("account-a", "table-a", "post-b")]
        for other in unrelated {
            XCTAssertEqual(ledger.status(for: other, isPublished: false, connection: .unavailable), .waitingForConnection)
        }
        ledger.finish(first, succeeded: false)
        for other in unrelated {
            XCTAssertEqual(ledger.status(for: other, isPublished: false, connection: .available), .saved)
        }
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .available), .failed)
    }

    func testResetDuringOutageCannotCarryOldFailureIntoRecoveredAccount() {
        let ledger = TablePostPublication()
        let old = ledger.begin(key())
        ledger.clear()
        ledger.finish(old, succeeded: false)
        let newPost = key("account-b")
        XCTAssertEqual(ledger.status(for: newPost, isPublished: false, connection: .unavailable), .waitingForConnection)
        XCTAssertEqual(ledger.status(for: newPost, isPublished: false, connection: .available), .saved)
        XCTAssertEqual(ledger.status(for: key(), isPublished: false, connection: .available), .saved)
    }

    func testAutomaticRecoveryIsLimitedToActiveRealTableWithKnownAvailablePath() {
        typealias Context = TablePostPublication.RecoveryContext
        XCTAssertTrue(Context(connection: .available, isForeground: true, isTableActive: true, isPreview: false, isIdentityReady: true).permitsRetry)
        for connection in [NetworkAvailability.State.unknown, .unavailable] {
            XCTAssertFalse(Context(connection: connection, isForeground: true, isTableActive: true, isPreview: false, isIdentityReady: true).permitsRetry)
        }
        XCTAssertFalse(Context(connection: .available, isForeground: false, isTableActive: true, isPreview: false, isIdentityReady: true).permitsRetry)
        XCTAssertFalse(Context(connection: .available, isForeground: true, isTableActive: false, isPreview: false, isIdentityReady: true).permitsRetry)
        XCTAssertFalse(Context(connection: .available, isForeground: true, isTableActive: true, isPreview: true, isIdentityReady: true).permitsRetry)
        XCTAssertFalse(Context(connection: .available, isForeground: true, isTableActive: true, isPreview: false, isIdentityReady: false).permitsRetry)
    }


    func testRecoveryWhileAnOlderPassFinishesIsCoalescedAndNotLost() {
        var pass = TablePostPublication.BacklogPass()
        XCTAssertTrue(pass.begin())
        XCTAssertFalse(pass.begin(), "A path recovery must not overlap the old writer")
        XCTAssertFalse(pass.begin(), "A concurrent pull joins the same follow-up")
        XCTAssertTrue(pass.finish(), "The recovered-path request still needs its turn")
        XCTAssertTrue(pass.begin())
        XCTAssertFalse(pass.finish(), "A failed pass alone must not schedule an endless retry loop")
    }

    func testASecondRecoveryDuringFollowUpGetsExactlyOneMorePass() {
        var pass = TablePostPublication.BacklogPass()
        XCTAssertTrue(pass.begin())
        XCTAssertFalse(pass.begin())
        XCTAssertTrue(pass.finish())
        XCTAssertTrue(pass.begin())
        XCTAssertFalse(pass.begin())
        XCTAssertTrue(pass.finish())
        XCTAssertTrue(pass.begin())
        XCTAssertFalse(pass.finish())
    }

    func testRecoveryDuringComposerFailureRetriesOnceWithoutFailureLoop() {
        let ledger = TablePostPublication()
        let post = key()
        let composer = ledger.begin(post)
        ledger.requestRecovery(for: post)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
        let before = ledger.recoveryRevision
        ledger.finish(composer, succeeded: false)
        XCTAssertEqual(ledger.recoveryRevision, before + 1)
        XCTAssertEqual(ledger.takeNextReadyRecovery(account: "account-a"), post)
        let recovered = ledger.begin(post)
        ledger.finish(recovered, succeeded: false)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"),
            "A generic retry failure is not a new connectivity event")
        XCTAssertEqual(ledger.recoveryRevision, before + 1)
    }

    func testSuccessfulComposerConsumesRecoveryWithoutAnotherAttempt() {
        let ledger = TablePostPublication()
        let post = key()
        let composer = ledger.begin(post)
        ledger.requestRecovery(for: post)
        let before = ledger.recoveryRevision
        ledger.finish(composer, succeeded: true)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
        XCTAssertEqual(ledger.recoveryRevision, before)
    }

    func testDeferredRecoveryWaitsForLastOverlappingAttempt() {
        let ledger = TablePostPublication()
        let post = key()
        let composer = ledger.begin(post)
        let other = ledger.begin(post)
        ledger.requestRecovery(for: post)
        let before = ledger.recoveryRevision
        ledger.finish(composer, succeeded: false)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
        XCTAssertEqual(ledger.recoveryRevision, before)
        ledger.finish(other, succeeded: false)
        XCTAssertEqual(ledger.recoveryRevision, before + 1)
        XCTAssertEqual(ledger.takeNextReadyRecovery(account: "account-a"), post)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
    }

    func testOneOverlappingSuccessCancelsRecoveryDespiteLaterFailure() {
        let ledger = TablePostPublication()
        let post = key()
        let first = ledger.begin(post)
        let second = ledger.begin(post)
        ledger.requestRecovery(for: post)
        ledger.finish(first, succeeded: true)
        ledger.finish(second, succeeded: false)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
        XCTAssertEqual(ledger.status(for: post, isPublished: true), .shared)
    }

    func testAccountChangeDropsBothReadyAndStillActiveRecoveryRequests() {
        let ledger = TablePostPublication()
        let ready = key()
        let active = key("account-a", "table-b", "post-b")
        let first = ledger.begin(ready)
        let second = ledger.begin(active)
        ledger.requestRecovery(for: ready)
        ledger.requestRecovery(for: active)
        ledger.finish(first, succeeded: false)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-b"))
        ledger.finish(second, succeeded: false)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"),
            "Returning to an old account cannot resurrect its abandoned requests")
    }

    func testResetInvalidatesDeferredRequestAndItsLateCompletion() {
        let ledger = TablePostPublication()
        let old = ledger.begin(key())
        ledger.requestRecovery(for: key())
        ledger.clear()
        let afterReset = ledger.recoveryRevision
        ledger.finish(old, succeeded: false)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
        XCTAssertEqual(ledger.recoveryRevision, afterReset)
    }

    func testConsumingOneRecoveryLeavesUnstartedRecordsReadyAcrossTaskRestart() {
        let ledger = TablePostPublication()
        let records = [key(), key("account-a", "table-b"), key("account-a", "table-a", "post-b")]
        for record in records {
            let attempt = ledger.begin(record)
            ledger.requestRecovery(for: record)
            ledger.finish(attempt, succeeded: false)
        }
        let first = ledger.takeNextReadyRecovery(account: "account-a")!
        // A SwiftUI task can restart while this attempt awaits the server.
        // The two unstarted records must still be independently consumable.
        let attempt = ledger.begin(first)
        let second = ledger.takeNextReadyRecovery(account: "account-a")!
        let third = ledger.takeNextReadyRecovery(account: "account-a")!
        XCTAssertEqual(Set([first, second, third]), Set(records))
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
        ledger.finish(attempt, succeeded: false)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
    }

    func testRepeatedRecoverySignalsCoalesceForOneActiveRecord() {
        let ledger = TablePostPublication()
        let attempt = ledger.begin(key())
        for _ in 0..<100 { ledger.requestRecovery(for: key()) }
        ledger.finish(attempt, succeeded: false)
        XCTAssertEqual(ledger.takeNextReadyRecovery(account: "account-a"), key())
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
    }

    func testFreshEventDuringRetryMayRequestExactlyOneFurtherRecovery() {
        let ledger = TablePostPublication()
        let first = ledger.begin(key())
        ledger.requestRecovery(for: key())
        ledger.finish(first, succeeded: false)
        XCTAssertEqual(ledger.takeNextReadyRecovery(account: "account-a"), key())
        let retry = ledger.begin(key())
        ledger.requestRecovery(for: key())
        ledger.finish(retry, succeeded: false)
        XCTAssertEqual(ledger.takeNextReadyRecovery(account: "account-a"), key())
        let final = ledger.begin(key())
        ledger.finish(final, succeeded: false)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
    }

    func testIdleOrBackgroundRequestsCannotStartUnpromptedWork() {
        let ledger = TablePostPublication()
        ledger.requestRecovery(for: key())
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
        let attempt = ledger.begin(key())
        ledger.requestRecovery(for: key())
        ledger.discardRecoveries()
        ledger.finish(attempt, succeeded: false)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
    }

    func testUnchosenDestinationMayResolveWithoutLosingItsRecoveryRequest() {
        let ledger = TablePostPublication()
        let initial = key("account-a", "")
        let resolved = key("account-a", "chosen-table")
        let attempt = ledger.begin(initial)
        ledger.requestRecovery(for: initial)
        ledger.move(attempt, to: resolved)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
        ledger.finish(attempt, succeeded: false)
        XCTAssertEqual(ledger.takeNextReadyRecovery(account: "account-a"), resolved)
        XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
    }

    func testKnownAudienceOrAccountMoveCannotTransferDeferredPermission() {
        for replacement in [key("account-b"), key("account-a", "different-table")] {
            let ledger = TablePostPublication()
            let attempt = ledger.begin(key())
            ledger.requestRecovery(for: key())
            ledger.move(attempt, to: replacement)
            ledger.finish(attempt, succeeded: false)
            XCTAssertNil(ledger.takeNextReadyRecovery(account: replacement.account))
            XCTAssertNil(ledger.takeNextReadyRecovery(account: "account-a"))
        }
    }

}
