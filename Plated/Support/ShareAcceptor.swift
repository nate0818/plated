import UIKit
import CloudKit
import SwiftUI
import SwiftData

/// Accepting a CloudKit share is the one thing SwiftUI still cannot do.
///
/// There is no `onOpenURL` for it and no scene modifier: the system hands
/// the invitation to `UIApplicationDelegate` (or the scene delegate) and
/// nowhere else. So the app carries a delegate for exactly this, wired
/// through `UIApplicationDelegateAdaptor`. Tapping a Plated invitation in
/// Messages lands here.
///
/// The accept itself is quick; what follows is not, so the pull is left to
/// the Table's own refresh rather than blocked on here.
final class ShareAcceptor: NSObject, UIApplicationDelegate {

    /// Set when a share has just been accepted, so the Table knows to pull
    /// even if it is already on screen and would otherwise sit still.
    @MainActor static let didAccept = Notification.Name("plated.share.accepted")

    /// Something changed at a table. Fetch, do not guess.
    @MainActor static let didChangeRemotely = Notification.Name("plated.table.remoteChange")

    /// An invitation has been read and is waiting for a yes. Posted on the
    /// main actor with `userInfo["received"]` a `Received`; the shell
    /// presents the dialog or the join sheet. Nothing is accepted before a
    /// person says so, on any road (docs/household.md section 7).
    @MainActor static let invitationReceived = Notification.Name("plated.invitation.received")

    /// What a link turned out to be, decided by the zone the share sits on
    /// rather than by what the link claimed.
    enum Received {
        case table(metadata: CKShare.Metadata, host: String, invite: String?)
        case household(metadata: CKShare.Metadata, root: HouseholdShare.RemoteRoot?, seat: String?, host: String)
        case failed(reason: String)
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Before anything else: a banner tapped to cold-start the app is
        // delivered to whatever delegate exists when launching finishes.
        NotificationRouter.install()
        // Silent CloudKit pushes need no permission prompt: this asks APNs
        // for a token, not the person for consent. Without it the
        // subscriptions below have nowhere to deliver.
        application.registerForRemoteNotifications()
        Task { await TableShare.subscribe() }
        // The Apple ID can change while the app is closed. Nothing observed
        // this, so `TableIdentity.cached` kept answering with the previous
        // account's id and the outbox would drain writes minted under it
        // into the new account's zone.
        NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                let before = TableIdentity.cached
                guard let now = await TableIdentity.confirm() else { return }
                guard now != before, !before.hasPrefix("local-") else { return }
                TableIdentity.reset()
            }
        }
        return true
    }

    /// The completion-handler spelling, so the selector UIKit looks up is
    /// the one written here rather than one the compiler synthesises.
    ///
    /// **Unverified on a simulator, in either spelling.** `xcrun simctl
    /// push` with a content-available payload reaches the process (a
    /// visible probe lands in `NotificationRouter.willPresent`) and this
    /// method stays silent, foreground or background. Whether that is the
    /// simulator or the wiring can only be settled on a phone, with a
    /// second device posting to a shared table and this console open.
    /// Until that is done, treat every silent-push claim in this file as
    /// a design, not a fact.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification info: [AnyHashable: Any],
        fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Only ours. A notification for another container is not a reason to
        // spend somebody's battery on a fetch.
        guard let note = CKNotification(fromRemoteNotificationDictionary: info),
              note.subscriptionID?.hasPrefix("plated-") == true else {
            // Printed rather than dropped: an empty console after a push
            // is indistinguishable from the push never arriving.
            print("[Push] ignored a remote notification: \(info.keys.map { "\($0)" })")
            completion(.noData)
            return
        }
        print("[Push] silent push from \(note.subscriptionID ?? "?")")
        // Fetch here, in the delegate, rather than leaving it to whichever
        // view happens to be alive. With the app in the background no view
        // is, and a silent push that nobody fetched for is a push that
        // never happened: Riley posts dinner and every other phone stays
        // dark until somebody opens the app. The fetch is what makes the
        // banner possible, and the banner is the whole point of the push.
        //
        // On a deadline. iOS gives a background fetch about thirty seconds
        // and remembers an app that overruns them by delivering it fewer
        // pushes, so a CloudKit round trip that hangs must not take the
        // completion handler down with it. The work carries on; only the
        // answer is given up on.
        Task {
            let finished = await withTaskGroup(of: Bool.self) { group -> Bool in
                group.addTask {
                    // One pull at a time: a push landing mid-refresh joins
                    // the refresh and runs once more after it, rather than
                    // racing it for the same change token.
                    await TablePull.pull(reason: "push")
                    return true
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(24))
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
            await MainActor.run {
                NotificationCenter.default.post(name: Self.didChangeRemotely, object: nil)
            }
            if !finished { print("[Push] fetch overran the background budget") }
            completion(finished ? .newData : .failed)
        }
    }

    /// Fold a delta into the store and say what in it is news.
    ///
    /// The seat step runs only when the share itself changed, because
    /// `Seats.reconcile` is a CloudKit round trip and a plate is not a
    /// reason to make one. What it finds newly joined is handed to the news
    /// so the host hears "Riley joined" the moment it happens rather than
    /// at the next launch, which is when the reconcile used to run.
    @MainActor
    static func absorb(_ changes: TableShare.Changes) async {
        let context = PlatedStore.shared.mainContext
        // Who am I, before deciding what is mine. A placeholder id would
        // make every one of this person's own posts look like a stranger's,
        // and the news would narrate their dinner back to them.
        await TableIdentity.confirmAndReattribute(in: context)
        TableShare.merge(changes, into: context)
        // Nights other phones planned, and what changed about them, kept
        // before the ledger is overwritten so the news can say "moved".
        let plans = PlanLedger.shared.absorb(changes, me: TableIdentity.cached)
        var joined: [HouseholdMember] = []
        var swept = PlanLedger.Delta()
        if changes.sharesChanged {
            let before = Set(Seats.all(in: context)
                .filter { $0.seat == .joined }.map(\.persistentModelID))
            await Seats.reconcile(in: context)
            Persist.save(context, "seats after push")
            joined = Seats.all(in: context).filter {
                $0.seat == .joined && !before.contains($0.persistentModelID)
            }
        }
        // An invitation the invitee answered stops being one that is
        // waiting. The claim is written by the phone that accepted, so it
        // arrives in this delta beside the seat it belongs to; settling
        // here rather than at the call site keeps every fold of a delta
        // saying the same thing about a seat. An empty claim list is a
        // no-op, which is what the household's plan-only delta carries.
        TableInvites.shared.settle(claims: changes.claims)
        if changes.householdShareChanged {
            // The head's own household zone keeps a departed member's
            // nights unless the head takes them out; nothing on the server
            // cascades. The Table share changing says nothing about this.
            swept = await TableShare.sweepDepartedPlans()
        }
        await TableNews.deliver(changes, newSeats: joined, plans: plans, context: context)
        // A swept night is not news (this phone took it off, not its
        // author), but a row and a banner about it are claims about a
        // night that no longer exists: withdrawn the way a wire deletion's
        // are, after the delivery so `deliver` cannot write them back.
        TableNews.retract(plans: swept.removed, context: context)
        if !plans.isEmpty || !swept.isEmpty {
            // A night whose cook is this person just arrived, moved or
            // left: the reminders read the ledger and must be rebuilt now,
            // not at the next visit to the Plan tab.
            let meals = (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []
            // No owner name goes in: whose night it is, is decided by
            // identity now (`HouseholdMember.isMe` locally,
            // `PlanLedger.isMine(cook:)` for a remote night), not by
            // matching the head of table's name.
            await NotificationScheduler.rebuild(meals: meals)
        }
    }

    // MARK: APNs

    /// The token the directory needs to reach this phone directly, for the
    /// one notice CloudKit cannot carry: an invitation from somebody whose
    /// table this phone is not yet at. Registered silently and only when
    /// this device has a directory session; see `Directory.registerDevice`.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[Push] APNs token \(hex.prefix(8))…")
        Task { await Directory.registerDevice(apnsToken: hex) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // The simulator, or no network. Silent pushes stop here, and the
        // Table falls back to being a pull, which it has always survived.
        print("[Push] no APNs token: \(error.localizedDescription)")
    }

    /// A raw `icloud.com/share` link, handed over by the system. The same
    /// road as every other: read, dispatch on the zone, and let the shell
    /// ask. Accepting here would seat a person at whatever a tapped link
    /// pointed at before they had seen whose it was.
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            if let url = metadata.share.url {
                await Self.received(shareURL: url, seat: nil, invite: nil, linkHost: "")
            } else {
                // No URL to re-fetch the root by; dispatch on what came.
                Self.dispatch(metadata, seat: nil, invite: nil, linkHost: "")
            }
        }
    }

    /// Every road ends here (docs/household.md section 7): a Universal
    /// Link, `plated://join`, the directory's `plated://invite` push, and
    /// the CloudKit delegate above. The metadata is fetched with the root
    /// record, because the join sheet is drawn from the root before
    /// anything is accepted, and the kind is decided by the zone the share
    /// sits on, never by what the URL claimed. Posts `invitationReceived`;
    /// accepts nothing.
    @MainActor
    static func received(shareURL: URL, seat: String?, invite: String?, linkHost: String) async {
        print("PLATED HOUSEHOLD: reading invitation \(shareURL.host ?? "?")\(seat.map { " seat \($0)" } ?? "")\(invite.map { " invite \($0)" } ?? "")")
        do {
            let metadata = try await metadataWithRoot(for: shareURL)
            dispatch(metadata, seat: seat, invite: invite, linkHost: linkHost)
        } catch {
            print("PLATED HOUSEHOLD: couldn't read that invitation: \(error.localizedDescription)")
            Haptic.warn()
            let reason: String
            if let ck = error as? CKError, ck.code == .unknownItem {
                // The link's own `h` is never trusted for a name, and with
                // no metadata there is no other source.
                reason = "This link doesn't work anymore. Ask the person who sent it for a new one."
            } else {
                switch await TableSync.accountState() {
                case .noAccount:
                    reason = "Sign in to iCloud on this iPhone to join, then open the link again."
                case .restricted:
                    reason = "iCloud is restricted on this iPhone, so Plated can't join a household."
                default:
                    reason = "Couldn't reach iCloud. Check your connection and open the link again."
                }
            }
            post(.failed(reason: reason))
        }
    }

    /// Which room this share opens. The zone name is the one fact a link
    /// cannot forge.
    @MainActor
    private static func dispatch(_ metadata: CKShare.Metadata, seat: String?, invite: String?, linkHost: String) {
        let zone = metadata.hierarchicalRootRecordID?.zoneID.zoneName
            ?? metadata.share.recordID.zoneID.zoneName
        let parts = metadata.ownerIdentity.nameComponents
        let owner = [parts?.givenName, parts?.familyName].compactMap { $0 }
            .joined(separator: " ").trimmingCharacters(in: .whitespaces)
        switch zone {
        case HouseholdShare.zoneName:
            let root = metadata.rootRecord.map(HouseholdShare.remoteRoot(from:))
            let host = owner.isEmpty ? (root?.hostName ?? "") : owner
            print("PLATED HOUSEHOLD: a household invitation from \(host.isEmpty ? "somebody unnamed" : host), root \(root == nil ? "missing" : "read")")
            post(.household(metadata: metadata, root: root, seat: seat, host: host))
        case TableShare.zoneName:
            let host = owner.isEmpty ? linkHost.trimmingCharacters(in: .whitespaces) : owner
            print("PLATED HOUSEHOLD: a table invitation from \(host.isEmpty ? "somebody unnamed" : host)")
            post(.table(metadata: metadata, host: host, invite: invite))
        default:
            print("PLATED HOUSEHOLD: a share on zone \"\(zone)\" is not an invitation")
            post(.failed(reason: "That link isn't a Plated invitation."))
        }
    }

    @MainActor
    private static func post(_ received: Received) {
        NotificationCenter.default.post(name: invitationReceived, object: nil, userInfo: ["received": received])
    }

    /// The share's metadata with its root record, so a household invitation
    /// can draw the join sheet before it is accepted. `TableShare.shareMetadata`
    /// fetches without the root and is left as it is.
    /// Internal rather than private: `HouseholdSync.join` asks for the root
    /// again when a road dispatched without one, because `removedIDs` lives
    /// there and a removed person may not join on the old link (§1).
    static func metadataWithRoot(for url: URL) async throws -> CKShare.Metadata {
        #if PLATED_CLOUDKIT
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            operation.shouldFetchRootRecord = true
            operation.rootRecordDesiredKeys = [
                "name", "hostName", "hostPhoto", "tableShareURL", "publishedAt",
                "removedIDs", "autoRotateOpenNights", "modifiedAt"
            ]
            var found: CKShare.Metadata?
            operation.perShareMetadataResultBlock = { _, result in
                if case .success(let metadata) = result { found = metadata }
            }
            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let found { continuation.resume(returning: found) }
                    else { continuation.resume(throwing: CKError(.unknownItem)) }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            CKContainer.default().add(operation)
        }
        #else
        throw CKError(.unknownItem)
        #endif
    }

    /// The old door, kept for any caller that still knocks on it: it now
    /// reads and asks rather than accepting.
    @MainActor
    static func accept(shareURL: URL) async {
        await received(shareURL: shareURL, seat: nil, invite: nil, linkHost: "")
    }

    /// A person said yes to a Table invitation. Accept, name the invitation
    /// the link carried so the host's next pull can settle it, and pull.
    @MainActor
    static func acceptTable(_ metadata: CKShare.Metadata, invite: String?) async -> Bool {
        guard await accept(metadata) else { return false }
        if let invite, !invite.isEmpty {
            let owner = metadata.hierarchicalRootRecordID?.zoneID.ownerName
                ?? metadata.share.recordID.zoneID.ownerName
            let claimed = await TableShare.pushClaim(inviteID: invite, zoneOwner: owner)
            print("PLATED HOUSEHOLD: table claim \(claimed ? "written" : "refused")")
        }
        await TablePull.pull(reason: "accept")
        return true
    }

    @MainActor
    private static func accept(_ metadata: CKShare.Metadata) async -> Bool {
        let ok = await TableShare.accept(metadata)
        if ok {
            Haptic.kiss()
            NotificationCenter.default.post(name: didAccept, object: nil)
            // Somebody's table just arrived on this phone. That is an
            // earned moment to ask about being told when they plate
            // something, and for a guest who never plans a night here it
            // is the only one there will be. Not from here, though: this
            // runs on a cold start, under the opener or the sign-in
            // screen, and a permission sheet over either is spent on
            // nothing. The shell asks once it is in front.
            NotificationScheduler.askSoon()
        } else {
            // A dead or revoked link. Not a crash and not a dialog —
            // the seat simply doesn't appear, and the host can re-send.
            Haptic.warn()
        }
        return ok
    }

    /// The share URL carried inside one of our own invitation links.
    /// Universal Link or the `plated://` fallback the web page offers.
    static func shareURL(from url: URL) -> URL? {
        let isOurs = (url.host == "plated.food" && url.path.hasPrefix("/join"))
            || (url.scheme == "plated" && url.host == "join")
        guard isOurs,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "s" })?.value,
              let share = URL(string: raw)
        else { return nil }
        return share
    }
}
