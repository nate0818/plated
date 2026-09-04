#if DEBUG
import Foundation
import SwiftData

/// Memory-only deletion checks. Injected cloud results never touch iCloud.
@MainActor
enum SchemaProbeRegressionChecks {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func run() async throws {
        let config = ModelConfiguration(schema: PlatedStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: PlatedStore.schema, configurations: [config])
        let context = container.mainContext
        var count = 0
        func expect(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Failure(description: name) }
            count += 1
            print("PLATED PROBE CHECK: PASS \(name)")
        }
        let probe = TablePost(authorName: "Prime", dishTitle: "Schema probe", caption: "Written to teach CloudKit the type.")
        probe.shareZoneOwner = "test-owner"
        let recordName = probe.shareRecordName
        context.insert(probe)
        let note = TableComment(authorName: "Prime", text: "Schema probe.")
        note.post = probe
        context.insert(note)
        let realPrime = TablePost(authorName: "Prime", dishTitle: "Dinner", caption: "My actual meal")
        let realTitle = TablePost(authorName: "Sam", dishTitle: "Schema probe", caption: "A real conversation")
        let nearMatch = TablePost(authorName: "Prime", dishTitle: "Schema probe", caption: "My own words")
        [realPrime, realTitle, nearMatch].forEach { context.insert($0) }
        try context.save()
        try expect(!probe.isUserContent && [realPrime, realTitle, nearMatch].allSatisfy(\.isUserContent), "Exact artifact matching preserves real people and similarly titled posts")
        await TableShare.removeSchemaProbes(from: context, retractRecord: { _, _ in false })
        let offline = try context.fetch(FetchDescriptor<TablePost>())
        try expect(offline.count == 4 && offline.filter(\.isUserContent).count == 3, "Offline cleanup hides the probe and retains its retry address")
        var targets: [String] = []
        await TableShare.removeSchemaProbes(from: context, retractRecord: { name, owner in
            targets.append(name + "|" + owner)
            return true
        })
        try expect(targets == [recordName + "|test-owner"], "Deletion uses only the artifact's original record and zone")
        let remaining = try context.fetch(FetchDescriptor<TablePost>())
        try expect(remaining.count == 3 && remaining.allSatisfy(\.isUserContent), "Confirmed remote deletion removes the cached artifact only")
        try expect(try context.fetch(FetchDescriptor<TableComment>()).isEmpty, "Probe comments are removed with the post")
        await TableShare.removeSchemaProbes(from: context, retractRecord: { _, _ in
            throwUnexpectedCall()
            return false
        })
        try expect(try context.fetchCount(FetchDescriptor<TablePost>()) == 3, "Repeated cleanup leaves real posts untouched")

        var wire = TableShare.RemotePost()
        wire.recordName = recordName
        wire.zoneOwner = "test-owner"
        wire.authorName = "Prime"
        wire.dishTitle = "Schema probe"
        wire.caption = "Written to teach CloudKit the type."
        var changes = TableShare.Changes()
        changes.posts = [wire]
        TableShare.merge(changes, into: context)
        try expect(try context.fetch(FetchDescriptor<TablePost>()).filter(\.isUserContent).count == 3, "Replayed cloud artifacts never become visible content")
        await TableShare.removeSchemaProbes(from: context, retractRecord: { _, _ in true })
        try expect(try context.fetchCount(FetchDescriptor<TablePost>()) == 3, "A replay is cleaned up again")
        print("PLATED PROBE CHECKS: \(count) passed")
    }

    private static func throwUnexpectedCall() {
        preconditionFailure("Cleanup attempted to retract a real post")
    }
}
#endif
