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
        Task { @MainActor in
            let ok = await TableShare.accept(metadata)
            if ok {
                Haptic.kiss()
                NotificationCenter.default.post(name: Self.didAccept, object: nil)
            } else {
                // A dead or revoked link. Not a crash and not a dialog —
                // the seat simply doesn't appear, and the host can re-send.
                Haptic.warn()
            }
        }
    }
}
