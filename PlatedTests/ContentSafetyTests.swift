import XCTest
@testable import Plated

@MainActor
final class ContentSafetyTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var safety: ContentSafety!

    override func setUp() {
        super.setUp()
        suiteName = "ContentSafetyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        safety = ContentSafety(defaults: defaults)
    }

    override func tearDown() {
        safety.reset()
        defaults.removePersistentDomain(forName: suiteName)
        safety = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStableIdentityWinsOverCollidingDisplayName() {
        let otherSam = ContentSafety.Author(identity: "other-sam", displayName: "Sam")
        XCTAssertTrue(safety.block(
            otherSam,
            currentIdentityIDs: ["my-sam"],
            currentDisplayNames: ["Sam"]
        ))

        XCTAssertTrue(safety.isBlocked(authorID: "other-sam", authorName: "Sam"))
        XCTAssertFalse(safety.isBlocked(authorID: "third-sam", authorName: "Sam"))
        XCTAssertTrue(ContentSafety(defaults: defaults).isBlocked(
            authorID: "other-sam",
            authorName: "Sam"
        ))
    }

    func testLegacyFallbackIsExactAndCaseInsensitive() {
        let legacy = ContentSafety.Author(identity: "", displayName: "Riley Chen")
        XCTAssertTrue(safety.block(
            legacy,
            currentIdentityIDs: ["me"],
            currentDisplayNames: ["Sam Rivera"]
        ))

        XCTAssertTrue(safety.isBlocked(authorID: "", authorName: "  RILEY CHEN "))
        XCTAssertFalse(safety.isBlocked(authorID: "", authorName: "Riley Jones"))
        XCTAssertFalse(safety.isBlocked(authorID: "riley-id", authorName: "Riley Chen"))
    }

    func testCannotBlockSelfByIdentityOrLegacyFirstName() {
        XCTAssertFalse(safety.block(
            .init(identity: "me", displayName: "Renamed"),
            currentIdentityIDs: ["me"],
            currentDisplayNames: ["Sam Rivera"]
        ))
        XCTAssertFalse(safety.block(
            .init(identity: "", displayName: "Sam"),
            currentIdentityIDs: ["me"],
            currentDisplayNames: ["Sam Rivera"]
        ))
        XCTAssertTrue(safety.blockedAuthors.isEmpty)
    }

    func testReportingIsIndependentFromConservativeLegacyBlocking() {
        let sameFirstName = ContentSafety.Author(identity: "", displayName: "Sam Jones")
        XCTAssertFalse(safety.canBlock(
            sameFirstName,
            currentIdentityIDs: ["me"],
            currentDisplayNames: ["Sam Rivera"]
        ))
        XCTAssertTrue(safety.canReport(
            sameFirstName,
            currentIdentityIDs: ["me"],
            knownToBeSelf: false
        ))
        XCTAssertTrue(safety.canReport(
            .init(identity: "", displayName: ""),
            currentIdentityIDs: ["me"],
            knownToBeSelf: false
        ))
        XCTAssertFalse(safety.canReport(
            .init(identity: "me", displayName: "Renamed"),
            currentIdentityIDs: ["me"],
            knownToBeSelf: false
        ))
        XCTAssertFalse(safety.canReport(
            .init(identity: "", displayName: "Sam Rivera"),
            currentIdentityIDs: ["me"],
            knownToBeSelf: true
        ))
    }

    func testUnblockRemovesPersistedEntry() {
        let author = ContentSafety.Author(identity: "riley", displayName: "Riley")
        XCTAssertTrue(safety.block(
            author,
            currentIdentityIDs: ["me"],
            currentDisplayNames: ["Sam"]
        ))
        safety.unblock(safety.blockedAuthors[0])

        XCTAssertFalse(safety.isBlocked(authorID: "riley", authorName: "Riley"))
        XCTAssertTrue(ContentSafety(defaults: defaults).blockedAuthors.isEmpty)
    }

    func testBlockedAuthorHidesTableActivityButNotSharedPlanActivity() {
        let author = ContentSafety.Author(identity: "riley", displayName: "Riley")
        XCTAssertTrue(safety.block(
            author,
            currentIdentityIDs: ["me"],
            currentDisplayNames: ["Sam"]
        ))

        let comment = PlatedNotification(
            kind: .commentAdded,
            actorName: "Riley",
            actorID: "riley"
        )
        let plan = PlatedNotification(
            kind: .planShared,
            actorName: "Riley",
            actorID: "riley"
        )
        XCTAssertTrue(safety.hidesTableActivity(comment))
        XCTAssertFalse(safety.hidesTableActivity(plan))
        XCTAssertTrue(safety.hidesTableNotice(
            kind: "comment",
            authorID: "riley",
            authorName: "Riley"
        ))
        XCTAssertFalse(safety.hidesTableNotice(
            kind: "plan",
            authorID: "riley",
            authorName: "Riley"
        ))
    }

    func testReportURLContainsReasonAndReferencesButNoContentOrLegacyName() throws {
        let target = ContentSafety.ReportTarget(
            kind: .comment,
            recordName: "note-opaque-123",
            authorID: "",
            authorName: "Private Person",
            zoneOwner: "zone-opaque-456",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let url = try XCTUnwrap(safety.reportURL(for: target, reason: .harassment))
        let decoded = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        let reloadedURL = try XCTUnwrap(
            ContentSafety(defaults: defaults).reportURL(for: target, reason: .harassment)
        )

        XCTAssertEqual(reloadedURL, url)
        XCTAssertTrue(decoded.contains("privacy@getplated.food"))
        XCTAssertTrue(decoded.contains("Bullying or harassment"))
        XCTAssertTrue(decoded.contains("note-opaque-123"))
        XCTAssertTrue(decoded.contains("zone-opaque-456"))
        XCTAssertFalse(decoded.contains("Private Person"))
        XCTAssertFalse(decoded.contains("secret comment text"))
    }
}
