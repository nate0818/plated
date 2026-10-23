import Foundation
import CloudKit
import CryptoKit
import UserNotifications

/// Durable hints about CONFIRMED CloudKit writes. The server re-reads the actual
/// record and share; no recipient, alert copy, or claimed identity is trusted.
/// Kept per device, never in SwiftData's mirrored store.
@MainActor
enum SocialPush {
    enum ConnectionOutcome: Equatable {
        case connected
        case waitingForDeviceToken
        case appleAccountRequired
        case serviceUnavailable
        case appleAccessDenied
        case appleIdentityUnavailable
        case temporarilyUnavailable

        var explanation: String? {
            switch self {
            case .connected: nil
            case .waitingForDeviceToken: "Notifications are still connecting. Plated will retry automatically."
            case .appleAccountRequired: "Sign in with Apple to receive Table notifications."
            case .serviceUnavailable: "Notifications are temporarily unavailable. Please try again later."
            case .appleAccessDenied: "Couldn’t connect notifications. Please try again later."
            case .appleIdentityUnavailable: "Couldn’t verify your iCloud account. Please try again."
            case .temporarilyUnavailable: "Couldn’t connect notifications. Please try again."
            }
        }
    }
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
    private static let receiptContextKey = "plated.socialPush.receiptContext.v1"
    private static var syncTask: Task<ConnectionOutcome, Never>?
    private static var syncRequestedAgain = false
    private static var sessionGeneration = 0
    private(set) static var lastConnectionOutcome: ConnectionOutcome?
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
        let token = (UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard).string(forKey: "plated.apns.latest") ?? ""
        return Directory.isRegistered && token.count == 64
            && UserDefaults.standard.double(forKey: receiptKey) > 0
            && UserDefaults.standard.string(forKey: receiptContextKey) == receiptContext(token: token, cloud: TableIdentity.cached)
    }
    private static func receiptContext(token: String, cloud: String) -> String {
        let data = Data("\(environment)|\(cloud)|\(token)".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static var installation: String {
        if let id = UserDefaults.standard.string(forKey: installationKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: installationKey)
        return id
    }
    static func confirmed(_ record: CKRecord) {
        let types = ["PlatedDish", "TablePost", "PlatedDishNote", "PlatedDishPlate", "PlatedDishBallot", "PlatedDishClaim", "PlatedHouseholdSeat"]
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
        syncRequestedAgain = true
        guard wake == nil else { return }
        let joiningExistingAttempt = syncTask != nil
        let generation = sessionGeneration
        wake = Task { @MainActor in
            defer { if sessionGeneration == generation { wake = nil } }
            // If Settings started a connection first, join it and then make
            // a fresh pass for the new work that arrived during that attempt.
            if joiningExistingAttempt { _ = await synchronize() }
            repeat {
                syncRequestedAgain = false
                _ = await synchronize()
            } while syncRequestedAgain && !Task.isCancelled
        }
    }
    static func reset() {
        sessionGeneration += 1
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
        syncTask?.cancel()
        syncTask = nil
        syncRequestedAgain = false
        lastConnectionOutcome = nil
        queue = []
        for key in [installationKey, bindingKey, receiptKey, receiptContextKey] { UserDefaults.standard.removeObject(forKey: key) }
    }
    @discardableResult
    static func synchronize() async -> ConnectionOutcome {
        if let syncTask { return await syncTask.value }
        let generation = sessionGeneration
        let task = Task { @MainActor in
            let outcome = await performSynchronization(generation: generation)
            if sessionGeneration == generation {
                syncTask = nil
                lastConnectionOutcome = outcome
            }
            return outcome
        }
        syncTask = task
        return await task.value
    }
    private static func performSynchronization(generation: Int) async -> ConnectionOutcome {
        guard Directory.isRegistered, !TableIdentity.isPlaceholder else { return .appleAccountRequired }
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("-plated-seed-sample"), !TableNews.rehearsing else { return .temporarilyUnavailable }
        #endif
        let me = TableIdentity.cached
        do {
            let snapshot = await preferences()
            let device = (UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard).string(forKey: "plated.apns.latest") ?? ""
            let bindingData = try JSONSerialization.data(withJSONObject: ["cloud": me, "token": device, "preferences": snapshot, "environment": environment], options: [.sortedKeys])
            let binding = SHA256.hash(data: bindingData).map { String(format: "%02x", $0) }.joined()
            let needsRegistration = UserDefaults.standard.string(forKey: bindingKey) != binding
                || Date.now.timeIntervalSince1970 - UserDefaults.standard.double(forKey: receiptKey) > 3600
                || !hasConfirmedInstallation
            let ready = queue.filter { $0.author == me && $0.retryAt <= .now && $0.queuedAt > Date.now.addingTimeInterval(-86400) }
            // A sender may still queue verified activity for other phones
            // while this phone is waiting for its own APNs token.
            guard (needsRegistration && device.count == 64) || !ready.isEmpty else {
                return needsRegistration ? .waitingForDeviceToken : .connected
            }
            let config = try await request(["action": "config"])
            guard config["enabled"] as? Bool == true, let apiToken = config["api_token"] as? String else { return .serviceUnavailable }
            if needsRegistration && device.count == 64 {
                let token = try await webToken(apiToken)
                let result = try await request(["action":"register", "installation":installation, "apns_token":device,
                    "web_token":token, "preferences":snapshot])
                guard !Task.isCancelled, sessionGeneration == generation,
                      result["cloud_id"] as? String == me, TableIdentity.cached == me,
                      Directory.isRegistered else { return .appleIdentityUnavailable }
                UserDefaults.standard.set(binding, forKey: bindingKey)
                UserDefaults.standard.set(receiptContext(token: device, cloud: me), forKey: receiptContextKey)
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: receiptKey)
                print("[SocialPush] verified device registered")
            }
            // Bounded so CloudKit/push maintenance never monopolizes a pull.
            for item in ready.prefix(8) {
                guard !Task.isCancelled, TableIdentity.cached == me, Directory.isRegistered else { return .appleAccountRequired }
                do {
                    let token = try await webToken(apiToken)
                    _ = try await request(["action":item.roomOnly ? "room" : "event", "web_token":token, "zone":item.zone, "owner":item.owner, "record":item.record])
                    remove(item)
                    print("[SocialPush] confirmed event queued for server delivery")
                } catch let error as ResponseError where isTerminalEventError(status: error.status, code: error.code) {
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
            return hasConfirmedInstallation ? .connected : .waitingForDeviceToken
        } catch let error as ResponseError {
            print("[SocialPush] registration deferred (\(error.status), \(error.code))")
            switch error.code {
            case "cloud_access_denied": return .appleAccessDenied
            case "cloud_identity_unavailable": return .appleIdentityUnavailable
            case "not_configured", "apns_not_configured": return .serviceUnavailable
            case "unauthorized": return .appleAccountRequired
            default: return .temporarilyUnavailable
            }
        } catch {
            // Never log CloudKit token-bearing URL/request objects.
            print("[SocialPush] verification unavailable; durable queue retained")
            return .temporarilyUnavailable
        }
    }
    /// Authentication/service failures do not establish that the event is
    /// invalid. Keep its durable hint for a fresh proof on the next attempt.
    static func isTerminalEventError(status: Int, code: String) -> Bool {
        if status == 410 { return code == "event_expired" }
        guard status == 400 || status == 403 else { return false }
        return ["invalid_identifier", "invalid_zone", "invalid_root", "invalid_share",
                "not_a_member", "not_your_event", "invalid_join", "invalid_event",
                "invalid_target", "invalid_post", "invalid_comment_target", "invalid_reply"]
            .contains(code)
    }
    static func localFallback(_ notices: [TableNews.Notice]) async -> [TableNews.Notice] {
        guard !TableNews.rehearsing, hasConfirmedInstallation else { return notices }
        let covered: Set<TableNews.Notice.Kind> = [.dish, .ask, .comment, .plates, .votes, .commentLikes, .kiss, .seat, .householdSeat]
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
