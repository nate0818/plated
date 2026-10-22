import Foundation
import CloudKit
import CryptoKit
import UserNotifications

/// Durable hints about CONFIRMED CloudKit writes. The server re-reads the actual
/// record and share; no recipient, alert copy, or claimed identity is trusted.
/// Kept per device, never in SwiftData's mirrored store.
@MainActor
enum SocialPush {
    struct Pending: Codable, Equatable {
        var zone: String
        var owner: String
        var record: String
        var author: String
        var roomOnly = false
        var generation = UUID()
        var queuedAt = Date.now
        var attempts = 0
        var retryAt = Date.distantPast
        var key: String { "\(author)|\(owner)|\(zone)|\(record)" }
    }
    private static let queueKey = "plated.socialPush.queue.v1"
    private static let installationKey = "plated.socialPush.installation.v1"
    private static let bindingKey = "plated.socialPush.binding.v1"
    private static let receiptKey = "plated.socialPush.registration.v1"
    private static var running = false
    private static var wake: Task<Void, Never>?
    private static var queue: [Pending] {
        get { UserDefaults.standard.data(forKey: queueKey).flatMap { try? JSONDecoder().decode([Pending].self, from: $0) } ?? [] }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }
    static var environment: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }
    /// This phone has received a successful, identity-verified server
    /// registration receipt. Settings must not call a preference toggle
    /// "on" proof that any phone can actually receive social alerts.
    static var hasConfirmedInstallation: Bool {
        Directory.isRegistered && UserDefaults.standard.double(forKey: receiptKey) > 0
    }
    private static var installation: String {
        if let id = UserDefaults.standard.string(forKey: installationKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: installationKey)
        return id
    }
    static func confirmed(_ record: CKRecord) {
        let types = ["PlatedDishNote", "PlatedDishPlate", "PlatedDishBallot", "PlatedDishClaim", "PlatedHouseholdSeat"]
        guard types.contains(record.recordType), !TableIdentity.isPlaceholder else { return }
        // A seat's creator can be the host who invited them; the claimant is
        // the person who joined. Post/comment authors use the other field.
        let isJoin = ["PlatedDishClaim", "PlatedHouseholdSeat"].contains(record.recordType)
        let identity = record[isJoin ? "userRecordName" : "authorID"] as? String ?? ""
        guard identity == TableIdentity.cached else { return }
        // A household profile edit is not a new acceptance; the server also
        // checks joinedAt and the seat's stable record name deduplicates it.
        if record.recordType == "PlatedHouseholdSeat" {
            guard record["seat"] as? String == "joined", let joined = record["joinedAt"] as? Date,
                  joined > Date.now.addingTimeInterval(-86400) else { return }
        }
        let zone = record.recordID.zoneID
        let owner = zone.ownerName == CKCurrentUserDefaultName ? "" : zone.ownerName
        let item = Pending(zone: zone.zoneName, owner: owner, record: record.recordID.recordName, author: identity)
        var work = queue.filter { $0.key != item.key && $0.queuedAt > Date.now.addingTimeInterval(-86400) }
        work.append(item)
        queue = work
        requestSync()
    }
    static func roomChanged(_ rootID: CKRecord.ID) {
        guard !TableIdentity.isPlaceholder else { return }
        let zone = rootID.zoneID
        var item = Pending(zone:zone.zoneName, owner:zone.ownerName == CKCurrentUserDefaultName ? "" : zone.ownerName,
                           record:rootID.recordName, author:TableIdentity.cached)
        item.roomOnly = true
        queue = queue.filter { $0.key != item.key } + [item]
        requestSync()
    }
    static func requestSync() {
        guard wake == nil else { return }
        wake = Task { @MainActor in
            defer { wake = nil }
            await synchronize()
        }
    }
    static func reset() {
        // Capture this session before Directory clears it. A subsequent
        // registration also replaces this exact APNs token's old binding.
        if let id = UserDefaults.standard.string(forKey: installationKey),
           var request = try? Directory.authenticatedRequest(path: "social") {
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["action":"unregister", "installation":id])
            request.timeoutInterval = 10
            Task { _ = try? await URLSession.shared.data(for: request) }
        }
        wake?.cancel()
        wake = nil
        queue = []
        for key in [installationKey, bindingKey, receiptKey] { UserDefaults.standard.removeObject(forKey: key) }
    }
    static func synchronize() async {
        guard !running, Directory.isRegistered, !TableIdentity.isPlaceholder else { return }
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("-plated-seed-sample"), !TableNews.rehearsing else { return }
        #endif
        running = true
        defer { running = false }
        let me = TableIdentity.cached
        do {
            let snapshot = await preferences()
            let device = (UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard).string(forKey: "plated.apns.latest") ?? ""
            let bindingData = try JSONSerialization.data(withJSONObject: ["cloud": me, "token": device, "preferences": snapshot, "environment": environment], options: [.sortedKeys])
            let binding = SHA256.hash(data: bindingData).map { String(format: "%02x", $0) }.joined()
            let needsRegistration = UserDefaults.standard.string(forKey: bindingKey) != binding
                || Date.now.timeIntervalSince1970 - UserDefaults.standard.double(forKey: receiptKey) > 3600
            let ready = queue.filter { $0.author == me && $0.retryAt <= .now && $0.queuedAt > Date.now.addingTimeInterval(-86400) }
            guard (needsRegistration && device.count == 64) || !ready.isEmpty else { return }
            let config = try await request(["action": "config"])
            guard config["enabled"] as? Bool == true, let apiToken = config["api_token"] as? String else { return }
            if needsRegistration && device.count == 64 {
                let token = try await webToken(apiToken)
                let result = try await request(["action":"register", "installation":installation, "apns_token":device,
                    "web_token":token, "preferences":snapshot])
                guard result["cloud_id"] as? String == me, TableIdentity.cached == me, Directory.isRegistered else { return }
                UserDefaults.standard.set(binding, forKey: bindingKey)
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: receiptKey)
                print("[SocialPush] verified device registered")
            }
            // Bounded so CloudKit/push maintenance never monopolizes a pull.
            for item in ready.prefix(8) {
                guard !Task.isCancelled, TableIdentity.cached == me, Directory.isRegistered else { return }
                do {
                    let token = try await webToken(apiToken)
                    _ = try await request(["action":item.roomOnly ? "room" : "event", "web_token":token, "zone":item.zone, "owner":item.owner, "record":item.record])
                    remove(item)
                    print("[SocialPush] confirmed event queued for server delivery")
                } catch let error as ResponseError where [400,403,410].contains(error.status) {
                    remove(item)
                    print("[SocialPush] event no longer eligible (\(error.status), \(error.code))")
                } catch {
                    var work = queue
                    if let index = work.firstIndex(where: { $0.generation == item.generation }) {
                        work[index].attempts += 1
                        work[index].retryAt = .now.addingTimeInterval(retryDelay(work[index].attempts))
                        queue = work
                    }
                    print("[SocialPush] event retained for retry")
                }
            }
        } catch let error as ResponseError {
            print("[SocialPush] registration deferred (\(error.status), \(error.code))")
        } catch {
            // Never log CloudKit token-bearing URL/request objects.
            print("[SocialPush] verification unavailable; durable queue retained")
        }
    }
    static func localFallback(_ notices: [TableNews.Notice]) async -> [TableNews.Notice] {
        guard !TableNews.rehearsing, Directory.isRegistered,
              UserDefaults.standard.object(forKey: receiptKey) != nil else { return notices }
        let covered: Set<TableNews.Notice.Kind> = [.comment, .plates, .votes, .commentLikes, .kiss, .seat, .householdSeat]
        let keys = Set(notices.filter { covered.contains($0.kind) }.flatMap { $0.key.split(separator: "|").map(String.init) })
        guard !keys.isEmpty, keys.count <= 100 else { return notices }
        do {
            let result = try await request(["action":"local_claim", "installation":installation, "keys":Array(keys)])
            guard let allowed = result["keys"] as? [String] else { return notices }
            let local = Set(allowed)
            return notices.filter { !covered.contains($0.kind) || !$0.key.split(separator:"|").map(String.init).allSatisfy { !local.contains($0) } }
        } catch { return notices } // A backend outage must not silence the existing local path.
    }

    static func retryDelay(_ attempts: Int) -> TimeInterval {
        min(1800, 15 * pow(2, Double(max(0, min(10, attempts - 1)))))
    }
    static var pending: [Pending] { queue }

    static func remove(_ item: Pending) {
        queue = queue.filter { $0.generation != item.generation }
    }
    private static func preferences() async -> [String: Any] {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorized = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        return ["enabled":NewsPreferences.tableOn, "authorized":authorized, "timeZone":TimeZone.current.identifier,
            "categories":Dictionary(uniqueKeysWithValues:NewsPreferences.Category.allCases.map { ($0.rawValue,NewsPreferences.isOn($0)) }),
            "muted":Array(NewsPreferences.mutedPosts()).sorted(),
            "blocked":ContentSafety.shared.blockedAuthors.compactMap { $0.id.hasPrefix("id:") ? String($0.id.dropFirst(3)) : nil }.sorted()]
    }
    private static func webToken(_ apiToken: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchWebAuthTokenOperation(apiToken: apiToken)
            operation.qualityOfService = .userInitiated
            operation.configuration.timeoutIntervalForRequest = 15
            operation.configuration.timeoutIntervalForResource = 30
            operation.fetchWebAuthTokenResultBlock = { continuation.resume(with: $0) }
            CKContainer.default().privateCloudDatabase.add(operation)
        }
    }
    private struct ResponseError: Error {
        let status: Int
        let code: String
    }
    private static func request(_ body: [String:Any]) async throws -> [String:Any] {
        var request = try Directory.authenticatedRequest(path: "social")
        request.timeoutInterval = 35
        var body = body
        body["environment"] = environment
        request.httpBody = try JSONSerialization.data(withJSONObject:body)
        let (data,response) = try await URLSession.shared.data(for:request)
        let json = (try? JSONSerialization.jsonObject(with:data) as? [String:Any]) ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ResponseError(status:status,code:json["error"] as? String ?? "unavailable") }
        return json
    }
}
