import CloudKit

enum CloudRecordPage {
    /// A failed asset/record is not an absent person or dish. Both zone
    /// readers must throw before committing the page's change token, so the
    /// next pull can retrieve the missing record instead of skipping it forever.
    static func records(_ results: [Result<CKRecord, Error>]) throws -> [CKRecord] {
        try results.map { try $0.get() }
    }
}
