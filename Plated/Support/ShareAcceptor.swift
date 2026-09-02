import UIKit
import CloudKit
import SwiftUI

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
