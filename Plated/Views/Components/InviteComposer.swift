import SwiftUI
import MessageUI
import ContactsUI

/// The system message composer, addressed to one person, carrying the
/// invitation.
///
/// Pre-addressed and pre-written, and NEVER pre-sent: the composer is the
/// user's own Messages sheet, and the send button is theirs to press. That
/// is both the only thing iOS allows and the right behaviour — an app that
/// texts your contacts on your behalf is an app you uninstall.
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

/// Pick somebody out of Contacts to invite.
///
/// The system picker rather than our own list, deliberately: it searches
/// every contact, it needs no permission prompt of its own (it runs out of
/// process and hands back only what was chosen), and it is the sheet people
/// already know. Onboarding's five-name shortlist is for the first run;
/// this is for the other 300 people you know.
struct ContactPicker: UIViewControllerRepresentable {
    var onPick: (_ name: String, _ phone: String?) -> Void
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        // Somebody with no number cannot be sent an invitation, so they are
        // not offered as one.
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return picker
    }

    func updateUIViewController(_ picker: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let parent: ContactPicker
        init(_ parent: ContactPicker) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = "\(contact.givenName) \(contact.familyName)"
                .trimmingCharacters(in: .whitespaces)
            parent.onPick(
                name.isEmpty ? contact.nickname : name,
                contact.phoneNumbers.first?.value.stringValue
            )
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.onCancel()
        }
    }
}

/// Who we are inviting and how to reach them, carried between the moment
/// somebody is chosen and the moment the composer opens.
struct InviteTarget: Identifiable {
    var id: String { name + (phone ?? "") }
    var name: String
    var phone: String?
}
