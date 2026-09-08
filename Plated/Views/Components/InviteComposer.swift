import SwiftUI
import MessageUI

/// The system message composer, addressed to one person, carrying the
/// invitation.
///
/// Pre-addressed and pre-written, and NEVER pre-sent: the composer is the
/// user's own Messages sheet, and the send button is theirs to press. That
/// is both the only thing iOS allows and the right behaviour — an app that
/// texts your contacts on your behalf is an app you uninstall.
///
/// Used for a resend, where the person is already a row. A fresh
/// invitation goes through `InviteFlow`, which drives the picker and this
/// same composer from UIKit; the SwiftUI `ContactPicker` that used to sit
/// beside this was the two-sheet chain that lost every pick, and is gone.
struct InviteComposer: UIViewControllerRepresentable {
    var recipients: [String]
    var body: String
    /// True only when the message actually went. A cancelled composer is
    /// not an invitation, and the seat must not claim otherwise.
    var onFinish: (Bool) -> Void

    static var isAvailable: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onFinish(result == .sent)
        }
    }
}

/// Who we are inviting and how to reach them, carried between the moment
/// somebody is chosen and the moment the composer opens.
struct InviteTarget: Identifiable {
    /// The seat's `shareRecordName`. Two invited seats called Sam are two
    /// seats (the roster insists on it everywhere else), so a name and a
    /// number cannot be the key: with it the composer's answer stamped
    /// "Invited today" on whichever Sam came first in the roster, and the
    /// one actually re-sent kept their old date.
    var seat: String
    var id: String { seat }
    var name: String
    var phone: String?
}
