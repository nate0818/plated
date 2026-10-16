import XCTest
@testable import Plated

final class DirectoryAccountDeletionTests: XCTestCase {
    func testOnlyAnExplicitDeletionConfirmationSucceeds() throws {
        let confirmed = try JSONSerialization.data(withJSONObject: ["deleted": true])
        XCTAssertNoThrow(try Directory.accountDeletionSucceeded(statusCode: 200, data: confirmed))

        let refused = try JSONSerialization.data(withJSONObject: ["deleted": false])
        XCTAssertThrowsError(
            try Directory.accountDeletionSucceeded(statusCode: 200, data: refused)
        ) { error in
            XCTAssertEqual(error as? Directory.AccountDeletionError, .invalidResponse)
        }
        XCTAssertThrowsError(
            try Directory.accountDeletionSucceeded(statusCode: 204, data: Data())
        ) { error in
            XCTAssertEqual(error as? Directory.AccountDeletionError, .invalidResponse)
        }
    }

    func testExpiredCredentialsStayDistinctFromServiceFailures() {
        XCTAssertThrowsError(
            try Directory.accountDeletionSucceeded(statusCode: 401, data: Data())
        ) { error in
            XCTAssertEqual(error as? Directory.AccountDeletionError, .sessionExpired)
        }
        XCTAssertThrowsError(
            try Directory.accountDeletionSucceeded(statusCode: 503, data: Data())
        ) { error in
            XCTAssertEqual(error as? Directory.AccountDeletionError, .unavailable)
        }
    }

    func testUnexpectedResponsesCannotClearTheLocalAccount() {
        for status in [300, 400, 422] {
            XCTAssertThrowsError(
                try Directory.accountDeletionSucceeded(statusCode: status, data: Data())
            ) { error in
                XCTAssertEqual(error as? Directory.AccountDeletionError, .invalidResponse)
            }
        }
    }
}
