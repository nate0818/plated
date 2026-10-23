import XCTest
import CloudKit
@testable import Plated

@MainActor
final class SocialPushTests: XCTestCase {
    private var previousIdentity = ""
    private var previousRehearsing = false
    private var previousPushDefaults: [String: Any] = [:]
    private var identityStore: UserDefaults { UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard }
    override func setUp() async throws {
        previousIdentity = TableIdentity.cached
        previousRehearsing = TableNews.rehearsing
        previousPushDefaults = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("plated.socialPush.") }
        for key in previousPushDefaults.keys { UserDefaults.standard.removeObject(forKey: key) }
        TableNews.rehearsing = true
        identityStore.set("notification-test-author", forKey: "plated.userRecordName")
    }
    override func tearDown() async throws {
        SocialPush.reset()
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("plated.socialPush.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for (key, value) in previousPushDefaults { UserDefaults.standard.set(value, forKey: key) }
        identityStore.set(previousIdentity, forKey: "plated.userRecordName")
        TableNews.rehearsing = previousRehearsing
    }
    private func record(_ type: String = "PlatedDishNote", name: String = "note-test", author: String = "notification-test-author") -> CKRecord {
        let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName:name,
            zoneID: CKRecordZone.ID(zoneName:"PlatedTable",ownerName:"owner-test")))
        record["authorID"] = author as CKRecordValue
        return record
    }
    func testOnlyConfirmedWritesByCurrentAccountEnterNotificationQueue() {
        SocialPush.confirmed(record(author:"someone-else"))
        SocialPush.confirmed(record("PlatedDish"))
        XCTAssertTrue(SocialPush.pending.isEmpty)
        SocialPush.confirmed(record())
        XCTAssertEqual(SocialPush.pending.map(\.record),["note-test"])
        XCTAssertEqual(SocialPush.pending.first?.owner,"owner-test")
    }
    func testLaterUndoReplacesQueuedReactionAndOldAcknowledgementCannotEraseIt() throws {
        let reaction = record("PlatedDishPlate",name:"plate-test")
        reaction["active"] = 1 as CKRecordValue
        SocialPush.confirmed(reaction)
        let first = try XCTUnwrap(SocialPush.pending.first)
        reaction["active"] = 0 as CKRecordValue
        SocialPush.confirmed(reaction)
        XCTAssertEqual(SocialPush.pending.count,1)
        XCTAssertNotEqual(SocialPush.pending.first?.generation,first.generation)
        SocialPush.remove(first)
        XCTAssertEqual(SocialPush.pending.count,1)
    }
    func testOldHouseholdProfileEditDoesNotBecomeJoinAlert() {
        let seat = record("PlatedHouseholdSeat",name:"seat-test",author:"host-who-created-the-invitation")
        seat["userRecordName"] = "notification-test-author" as CKRecordValue
        seat["seat"] = "joined" as CKRecordValue
        seat["joinedAt"] = Date.now.addingTimeInterval(-172800) as CKRecordValue
        SocialPush.confirmed(seat)
        XCTAssertTrue(SocialPush.pending.isEmpty)
        seat["joinedAt"] = Date.now as CKRecordValue
        SocialPush.confirmed(seat)
        XCTAssertEqual(SocialPush.pending.count,1)
    }
    func testSessionResetDropsPreviousAccountsWork() {
        SocialPush.confirmed(record())
        SocialPush.reset()
        XCTAssertTrue(SocialPush.pending.isEmpty)
    }
    func testBackoffIsBounded() {
        XCTAssertEqual([1,2,3,40].map(SocialPush.retryDelay),[15,30,60,1800])
    }
    func testAuthenticationFailureDoesNotDiscardConfirmedActivity() {
        for code in ["cloud_identity_unavailable", "cloud_access_denied", "cloud_auth_required", "unauthorized"] {
            XCTAssertFalse(SocialPush.isTerminalEventError(status: 403, code: code))
        }
        XCTAssertFalse(SocialPush.isTerminalEventError(status: 503, code: "cloud_token_refresh_required"))
        XCTAssertTrue(SocialPush.isTerminalEventError(status: 403, code: "not_a_member"))
        XCTAssertTrue(SocialPush.isTerminalEventError(status: 403, code: "not_your_event"))
        XCTAssertTrue(SocialPush.isTerminalEventError(status: 410, code: "event_expired"))
    }
}
