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
        let before = TableIdentity.cached
        if let real = await TableIdentity.confirm(), real != before {
            TableLedger.shared.reattribute(from: before, to: real)
            TableOutbox.shared.reattribute(from: before, to: real)
        }
        TableShare.merge(changes, into: context)
        var joined: [HouseholdMember] = []
        if changes.sharesChanged {
            let before = Set(Seats.all(in: context)
                .filter { $0.seat == .joined }.map(\.persistentModelID))
            await Seats.reconcile(in: context)
            Persist.save(context, "seats after push")
            joined = Seats.all(in: context).filter {
                $0.seat == .joined && !before.contains($0.persistentModelID)
            }
        }
        await TableNews.deliver(changes, newSeats: joined, context: context)
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

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        Task { @MainActor in await Self.accept(metadata) }
    }

    /// Accept an invitation that arrived through our own domain rather than
    /// through iCloud's.
    ///
    /// A raw `icloud.com/share` link is handed to the delegate above by the
    /// system. A `plated.food/join?s=…` link is not — it is a Universal
    /// Link, so it arrives as an ordinary URL and the metadata has to be
    /// fetched before it can be accepted. Both roads end in the same place.
    ///
    /// The wrapper exists because the raw link is a dead end for anyone who
    /// doesn't have Plated yet: iCloud shows them a page about a share they
    /// cannot open. Ours shows them what Plated is and where to get it.
    @MainActor
    static func accept(shareURL: URL) async {
        do {
            let metadata = try await TableShare.shareMetadata(for: shareURL)
            await accept(metadata)
        } catch {
            print("PLATED SHARE: couldn't read that invitation — \(error.localizedDescription)")
            Haptic.warn()
        }
    }

    @MainActor
    private static func accept(_ metadata: CKShare.Metadata) async {
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
