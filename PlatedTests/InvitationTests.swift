import XCTest
@testable import Plated

/// Link grammar, and the one road nobody could open.
///
/// `Seats.confirmSent` hands the directory the WRAPPED plated.food link, and
/// `/invite` nests it verbatim under `plated://invite?s=`. Read without
/// unwrapping, that `s` went to `CKFetchShareMetadataOperation` as a
/// plated.food URL, CloudKit refused it, and the one push the directory
/// sends told the person the link was dead.
final class InvitationParseTests: XCTestCase {

    private let share = "https://www.icloud.com/share/0abcdef1234567890"

    private func push(_ inner: String, from: String = "Nate", kind: String = "household") -> URL {
        URL(string: "plated://invite?s=\(inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)&from=\(from)&k=\(kind)")!
    }

    func testDirectoryPushUnwrapsANestedHouseholdLink() throws {
        let inner = "https://plated.food/join/household?s=\(share)&h=Nate&seat=seat-42"
        let parsed = try XCTUnwrap(Invitation.parse(push(inner)))
        XCTAssertEqual(parsed.share.host, "www.icloud.com")
        XCTAssertEqual(parsed.kind, .household)
        XCTAssertEqual(parsed.seat, "seat-42")
        XCTAssertNil(parsed.invite)
        // The host is the outer link's `from`: the server verified that one,
        // and the inner `h` is never trusted.
        XCTAssertEqual(parsed.host, "Nate")
    }

    func testDirectoryPushUnwrapsANestedTableLink() throws {
        let inner = "https://plated.food/join?s=\(share)&h=Nate&i=invite-7"
        let parsed = try XCTUnwrap(Invitation.parse(push(inner, kind: "table")))
        XCTAssertEqual(parsed.share.host, "www.icloud.com")
        XCTAssertEqual(parsed.kind, .table)
        XCTAssertEqual(parsed.invite, "invite-7")
        XCTAssertNil(parsed.seat)
    }

    /// The inner link is the authority on which room this opens, so a push
    /// whose `k` disagrees with the link it carries follows the link.
    func testTheInnerLinkDecidesTheKind() throws {
        let inner = "https://plated.food/join/household?s=\(share)&seat=seat-9"
        let parsed = try XCTUnwrap(Invitation.parse(push(inner, kind: "table")))
        XCTAssertEqual(parsed.kind, .household)
        XCTAssertEqual(parsed.seat, "seat-9")
    }

    /// The server nests exactly one level. A hand-crafted link that nests
    /// further is nothing, rather than something handed to CloudKit.
    func testATwoDeepNestIsRefused() {
        let innermost = "https://plated.food/join?s=\(share)"
        let middle = "https://plated.food/join?s=\(innermost.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)"
        XCTAssertNil(Invitation.parse(push(middle, kind: "table")))
    }

    /// The ordinary road is unchanged: a link carrying the share itself.
    func testAPlainHouseholdLinkStillReads() throws {
        let url = URL(string: "https://plated.food/join/household?s=\(share)&h=Nate&seat=seat-1")!
        let parsed = try XCTUnwrap(Invitation.parse(url))
        XCTAssertEqual(parsed.share.absoluteString, share)
        XCTAssertEqual(parsed.kind, .household)
        XCTAssertEqual(parsed.seat, "seat-1")
        XCTAssertEqual(parsed.host, "Nate")
    }

    /// The innermost URL still has to be https: a link that could smuggle
    /// an arbitrary scheme into the accept path is not an invitation.
    func testANonHTTPSShareIsRefused() {
        let url = URL(string: "https://plated.food/join?s=file:///etc/passwd")!
        XCTAssertNil(Invitation.parse(url))
    }

    func testWrappedRoundTrips() throws {
        let link = Invitation.wrapped(
            URL(string: share)!, hostName: "Nate", kind: .household, seat: "seat-3", invite: nil
        )
        let parsed = try XCTUnwrap(Invitation.parse(link))
        XCTAssertEqual(parsed.share.absoluteString, share)
        XCTAssertEqual(parsed.kind, .household)
        XCTAssertEqual(parsed.seat, "seat-3")
    }

    /// A Table link carries an invite id and never a seat, whatever it was
    /// handed: a seat belongs to the household roster and nothing at the
    /// Table can claim one.
    func testATableLinkCarriesTheInviteAndNeverASeat() throws {
        let link = Invitation.wrapped(
            URL(string: share)!, hostName: "Nate", kind: .table, seat: "seat-7", invite: "inv-3"
        )
        XCTAssertEqual(link.path, "/join")
        let parsed = try XCTUnwrap(Invitation.parse(link))
        XCTAssertEqual(parsed.kind, .table)
        XCTAssertEqual(parsed.invite, "inv-3")
        XCTAssertNil(parsed.seat)
    }

    /// The page's own fallback button, as `web/app/join` spells it. The
    /// host arrives percent-encoded, so a name with a space must come back
    /// as a space and never as a "+".
    func testTheAppSchemeFallbackReadsTheSameLink() throws {
        let s = share.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let parsed = try XCTUnwrap(
            Invitation.parse(URL(string: "plated://join?s=\(s)&k=household&seat=seat-7&h=Mary%20Ann")!)
        )
        XCTAssertEqual(parsed.kind, .household)
        XCTAssertEqual(parsed.seat, "seat-7")
        XCTAssertEqual(parsed.host, "Mary Ann")
    }

    /// The directory's push puts the host under `from`, not `h`.
    func testTheDirectoryPushNamesTheHostUnderFrom() throws {
        let read = try XCTUnwrap(Invitation.parse(push(share, from: "Nate")))
        XCTAssertEqual(read.host, "Nate")
        XCTAssertEqual(read.kind, .household)
        XCTAssertEqual(read.share.absoluteString, share)
    }

    /// One of our hosts with a path we do not serve is not an invitation.
    func testAnUnknownPlatedFoodPathIsNotAnInvitation() {
        let s = share.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        XCTAssertNil(Invitation.parse(URL(string: "https://plated.food/somewhere?s=\(s)")!))
    }
}
