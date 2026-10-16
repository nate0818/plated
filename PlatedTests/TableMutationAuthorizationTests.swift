import XCTest
@testable import Plated

/// Destructive Table controls must key ownership on identity, not a byline.
/// These are intentionally pure tests: no CloudKit account or store timing
/// can turn a same-name collision into a passing result.
@MainActor
final class TableMutationAuthorizationTests: XCTestCase {

    private let myIDs = ["me-user", "me-participant"]
    private let myNames = ["Sam Rivera", "Sam"]

    func testStampedForeignPostWithMyDisplayNameIsNotMine() {
        let post = TablePost(authorName: "Sam Rivera", dishTitle: "Ragù")
        post.authorID = "somebody-else"
        post.isRemote = false
        post.shareZoneOwner = ""

        XCTAssertFalse(TableMutationAuthorization.owns(
            post: post, identityIDs: myIDs, displayNames: myNames
        ))
    }

    func testStableAliasOwnsPostRegardlessOfPresentationFlags() {
        let post = TablePost(authorName: "Old display name", dishTitle: "Ragù")
        post.authorID = "me-participant"
        post.isRemote = true
        post.shareZoneOwner = "another-zone"

        XCTAssertTrue(TableMutationAuthorization.owns(
            post: post, identityIDs: myIDs, displayNames: myNames
        ))
    }

    func testLegacyNameFallbackIsLimitedToOwnZoneRows() {
        let local = TablePost(authorName: "Sam Rivera", dishTitle: "Ragù")
        local.authorID = ""
        local.isRemote = false
        local.shareZoneOwner = ""
        XCTAssertTrue(TableMutationAuthorization.owns(
            post: local, identityIDs: myIDs, displayNames: myNames
        ))

        let shared = TablePost(authorName: "Sam Rivera", dishTitle: "Ragù")
        shared.authorID = ""
        shared.isRemote = false
        shared.shareZoneOwner = "host-user"
        XCTAssertFalse(TableMutationAuthorization.owns(
            post: shared, identityIDs: myIDs, displayNames: myNames
        ))
    }

    func testStampedForeignCommentWithMyDisplayNameCannotBeDeleted() {
        let post = TablePost(authorName: "Riley", dishTitle: "Soup")
        post.authorID = "riley-user"
        post.isRemote = true
        post.shareZoneOwner = "riley-user"
        let comment = TableComment(
            authorName: "Sam Rivera", text: "Looks good", authorID: "other-sam"
        )

        XCTAssertFalse(TableMutationAuthorization.canDelete(
            comment: comment, on: post,
            identityIDs: myIDs, displayNames: myNames
        ))
    }

    func testStableIdentityCanDeleteOwnCommentOnRemotePost() {
        let post = TablePost(authorName: "Riley", dishTitle: "Soup")
        post.authorID = "riley-user"
        post.isRemote = true
        post.shareZoneOwner = "riley-user"
        let comment = TableComment(
            authorName: "Renamed Sam", text: "Looks good", authorID: "me-user"
        )

        XCTAssertTrue(TableMutationAuthorization.canDelete(
            comment: comment, on: post,
            identityIDs: myIDs, displayNames: myNames
        ))
    }

    func testPostOwnerCanModerateForeignComment() {
        let post = TablePost(authorName: "Renamed Sam", dishTitle: "Soup")
        post.authorID = "me-user"
        let comment = TableComment(
            authorName: "Riley", text: "Looks good", authorID: "riley-user"
        )

        XCTAssertTrue(TableMutationAuthorization.canDelete(
            comment: comment, on: post,
            identityIDs: myIDs, displayNames: myNames
        ))
    }

    func testUnstampedCommentOnStampedForeignPostGetsNoNameFallback() {
        let post = TablePost(authorName: "Riley", dishTitle: "Soup")
        post.authorID = "riley-user"
        let comment = TableComment(authorName: "Sam Rivera", text: "Legacy")

        XCTAssertFalse(TableMutationAuthorization.canDelete(
            comment: comment, on: post,
            identityIDs: myIDs, displayNames: myNames
        ))
    }
}
