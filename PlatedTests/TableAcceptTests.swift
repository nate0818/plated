import XCTest
import CloudKit
@testable import Plated

/// The join that told everybody the same untrue thing.
///
/// An invited person tapped a Table link, tapped Join the Table, and got
/// "Couldn't join the Table. Check your connection and open the link
/// again." The connection was the one cause that could be ruled out: the
/// invitation had just been read off iCloud to draw the dialog they were
/// answering. `TableShare.accept` returned a `Bool` and threw the CloudKit
/// error away, so a revoked link, a signed-out phone, a participant-only
/// share and a seat already taken all arrived as that sentence, and the
/// console said nothing at all.
///
/// These hold the classifier the app uses, not a copy of it.
final class TableAcceptTests: XCTestCase {

    /// Every outcome, so the invariant below covers the whole enum rather
    /// than the ones somebody remembered.
    private let all: [TableShare.Accepted] = [
        .joined, .alreadyJoined, .ownTable, .gone, .notInvited,
        .noAccount, .restricted, .unreachable, .refused(code: 2)
    ]

    /// A person is at the table or is told why not. Never both, never
    /// neither: a silent refusal is the failure this whole change is
    /// about, and a sentence over a seat that was taken is a lie the
    /// other way.
    func testSeatedAndSpokenAreExclusive() {
        for outcome in all {
            XCTAssertEqual(
                outcome.seated, outcome.line == nil,
                "\(outcome) is \(outcome.seated ? "seated" : "refused") and \(outcome.line == nil ? "says nothing" : "says something")"
            )
        }
    }

    /// The bug itself. Only a genuine network failure may blame the
    /// network, because by the time this sentence is shown the share has
    /// already been read off iCloud once.
    func testOnlyAnUnreachableICloudBlamesTheConnection() {
        for outcome in all {
            let blames = outcome.line?.contains("connection") == true
            XCTAssertEqual(blames, outcome == .unreachable, "\(outcome): \(outcome.line ?? "no line")")
        }
    }

    func testARevokedLinkSaysTheLinkIsDead() {
        let outcome = TableShare.accepted(from: .unknownItem, account: .available)
        XCTAssertEqual(outcome, .gone)
        XCTAssertEqual(outcome.line, "This link doesn't work anymore. Ask the person who sent it for a new one.")
    }

    /// Tables minted before the link became the credential are still
    /// participant-only, and a link already sitting in somebody's messages
    /// points at one until its host sends a new invitation.
    func testAParticipantOnlyShareAsksForANewLink() {
        XCTAssertEqual(TableShare.accepted(from: .participantMayNeedVerification, account: .available), .notInvited)
        XCTAssertEqual(TableShare.accepted(from: .permissionFailure, account: .available), .notInvited)
    }

    /// Already a participant is a seat, not a refusal. `CKContainer.accept`
    /// throws on a second accept, so this is what a person who opened the
    /// link twice was being told they could not do.
    func testAlreadySharedIsASeat() {
        let outcome = TableShare.accepted(from: .alreadyShared, account: .available)
        XCTAssertEqual(outcome, .alreadyJoined)
        XCTAssertTrue(outcome.seated)
        XCTAssertNil(outcome.line)
    }

    /// The error alone cannot tell a flaky network from a phone with no
    /// iCloud on it, which is why the account state is an argument.
    func testASignedOutPhoneIsNeverToldToCheckItsConnection() {
        XCTAssertEqual(TableShare.accepted(from: .networkFailure, account: .noAccount), .noAccount)
        XCTAssertEqual(TableShare.accepted(from: .notAuthenticated, account: .temporarilyUnavailable), .noAccount)
        XCTAssertEqual(TableShare.accepted(from: .internalError, account: .noAccount), .noAccount)
        XCTAssertEqual(TableShare.accepted(from: .notAuthenticated, account: .restricted), .restricted)
        XCTAssertEqual(TableShare.accepted(from: .managedAccountRestricted, account: .available), .restricted)
    }

    /// A code nobody has a sentence for still gets a true one, and keeps
    /// the number so the console can name it.
    func testAnUnknownCodeKeepsItsNumber() {
        XCTAssertEqual(
            TableShare.accepted(from: .badContainer, account: .available),
            .refused(code: CKError.Code.badContainer.rawValue)
        )
    }

    /// Only the outcome that means "later" is retried, and the retry is
    /// what `TableShare.accept` spends a person's second of waiting on.
    func testOnlyLaterIsWorthATry() {
        for outcome in all {
            XCTAssertEqual(outcome.isTransient, outcome == .unreachable, "\(outcome)")
        }
    }
}
