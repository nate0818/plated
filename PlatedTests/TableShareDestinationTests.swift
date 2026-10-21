import XCTest
@testable import Plated

@MainActor
final class TableShareDestinationTests: XCTestCase {

    private func destination(
        _ owner: String, _ title: String = "A Table", isOwn: Bool = false
    ) -> TableShare.Destination {
        TableShare.Destination(ownerID: owner, title: title, isOwn: isOwn)
    }

    func testPreMintedRecordNameDoesNotMakeFirstPublicationAnUpdate() {
        let post = TablePost(authorName: "Nate", dishTitle: "Tacos")

        XCTAssertFalse(post.shareRecordName.isEmpty, "identity is minted before publication")
        XCTAssertFalse(post.isPublished)
        XCTAssertEqual(
            TableShare.publicationOwner(
                for: post,
                destinations: [destination("host-id", "Riley's Table")]
            ),
            "host-id"
        )
    }

    func testUnassignedFirstPublicationRefusesToGuessBetweenTables() {
        let post = TablePost(authorName: "Nate", dishTitle: "Tacos")

        XCTAssertNil(TableShare.publicationOwner(
            for: post,
            destinations: [
                destination("host-a", "Sam's Table"),
                destination("host-b", "Riley's Table")
            ]
        ))
    }

    func testFailedFirstPublicationStaysPinnedToItsChosenOwner() {
        let post = TablePost(authorName: "Nate", dishTitle: "Tacos")
        post.shareZoneOwner = "host-b"

        XCTAssertEqual(
            TableShare.publicationOwner(
                for: post,
                destinations: [destination("host-a", "Sam's Table")]
            ),
            "host-b"
        )
    }

    func testPublishedLegacyOwnPostKeepsTheEmptyOwnerConvention() {
        let post = TablePost(authorName: "Nate", dishTitle: "Tacos")
        post.isPublished = true
        post.shareZoneOwner = ""

        XCTAssertEqual(
            TableShare.publicationOwner(
                for: post,
                destinations: [destination("someone-else", "Someone else's Table")]
            ),
            ""
        )
    }

    func testMemberDestinationsPutTheHouseholdFirstAndExcludePrivateOwnTable() {
        let choices = TableShare.orderedDestinations(
            own: destination("me", "My old Table", isOwn: true),
            householdOwnerID: "household-host",
            shared: [
                destination("other-host", "Zoe's Table"),
                destination("household-host", "Our Table"),
                destination("other-host", "Duplicate")
            ]
        )

        XCTAssertEqual(choices.map(\.ownerID), ["household-host", "other-host"])
        XCTAssertFalse(choices.contains(where: \.isOwn))
    }

    func testHostDestinationsPutOwnFirstAndGiveUntitledTablesReadableLabels() {
        let choices = TableShare.orderedDestinations(
            own: destination("me", "   ", isOwn: true),
            householdOwnerID: nil,
            shared: [
                destination("z-host", ""),
                destination("a-host", "Alex's Table")
            ]
        )

        XCTAssertEqual(choices.map(\.ownerID), ["me", "z-host", "a-host"])
        XCTAssertEqual(choices.map(\.label), [
            "Your Table", "A Table you joined", "Alex's Table"
        ])
    }
    func testDetachedNewPostCannotConsumeIdentityOrStartPublication() async {
        let post = TablePost(authorName: "Nate", dishTitle: "Offline draft")
        post.shareRecordName = ""
        let account = TableIdentity.cached
        let result = await TableShare.publish(post, hostName: "Nate")
        XCTAssertNil(result)
        XCTAssertNil(post.modelContext)
        XCTAssertEqual(post.shareRecordName, "", "Reject before minting or starting a wire attempt")
        XCTAssertFalse(post.isPublished)
        XCTAssertEqual(TableIdentity.cached, account)
    }

    func testDetachedPublishedEchoCannotBypassIdentityMigrationPreflight() async {
        let post = TablePost(authorName: "Nate", dishTitle: "Existing post")
        post.authorID = "confirmed-author"
        post.shareRecordName = "existing-record"
        post.shareZoneOwner = "chosen-table"
        post.isPublished = true
        let result = await TableShare.publish(post, hostName: "Nate")
        XCTAssertNil(result)
        XCTAssertEqual(post.authorID, "confirmed-author")
        XCTAssertEqual(post.shareRecordName, "existing-record")
        XCTAssertEqual(post.shareZoneOwner, "chosen-table")
        XCTAssertTrue(post.isPublished, "Rejecting a detached edit cannot erase its prior receipt")
    }

}
