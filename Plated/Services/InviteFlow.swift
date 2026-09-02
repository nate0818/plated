import UIKit
import ContactsUI
import MessageUI

/// Pick a person, then text them an invitation — driven from UIKit rather
/// than through SwiftUI sheets.
///
/// **Why it isn't a `.sheet`.** This flow is three presentations deep: the
/// household sheet, the contact picker on top of it, the message composer on
/// top of that. SwiftUI will not reliably do this. Two `.sheet` modifiers on
/// one view is undefined behaviour to begin with, and
/// `CNContactPickerViewController` dismisses *itself* — so the framework
/// never learns the sheet is gone, `onDismiss` may never fire, and the
/// teardown can take the sheet underneath with it. The symptom is exactly
/// what it looked like: you choose somebody, everything disappears, nothing
/// happens, nothing is logged, because no code ever ran.
///
/// UIKit has none of that ambiguity. `dismiss(animated:completion:)` calls
/// its completion, always, after the controller is actually gone — which is
/// the one guarantee this whole flow needs.
@MainActor
enum InviteFlow {

    enum Result {
        /// They picked somebody and the message actually sent.
        case sent(name: String, phone: String?)
        /// Picked somebody, but nothing was sent — cancelled, or failed.
        case notSent(name: String, phone: String?)
        /// Never got as far as a person.
        case cancelled
        /// A person, but no link to give them, so nothing was offered.
        case noLink(name: String, reason: String)
    }

    /// Present the picker, then the composer, then report what happened.
    /// `prepare` is the link-minting step, run between the two while nothing
    /// is on screen.
    static func run(
        hostName: String,
        prepare: @escaping (String?) async -> TableShare.InviteOutcome,
        completion: @escaping (Result) -> Void
    ) {
        guard let top = topViewController() else {
            completion(.cancelled)
            return
        }
        let picker = CNContactPickerViewController()
        let delegate = PickerDelegate(hostName: hostName, prepare: prepare, completion: completion)
        picker.delegate = delegate
        // Somebody with no number cannot be sent an invitation.
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        // The delegate must outlive this call — CNContactPicker holds its
        // delegate weakly, and a local would be gone before the first tap.
        retained = delegate
        top.present(picker, animated: true)
    }

    /// The only strong reference to the in-flight delegate.
    private static var retained: AnyObject?

    private final class PickerDelegate: NSObject, CNContactPickerDelegate, MFMessageComposeViewControllerDelegate {
        private let hostName: String
        private let prepare: (String?) async -> TableShare.InviteOutcome
        private let completion: (Result) -> Void
        private var name = ""
        private var phone: String?

        init(
            hostName: String,
            prepare: @escaping (String?) async -> TableShare.InviteOutcome,
            completion: @escaping (Result) -> Void
        ) {
            self.hostName = hostName
            self.prepare = prepare
            self.completion = completion
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let full = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            name = full.isEmpty ? contact.nickname : full
            phone = contact.phoneNumbers.first?.value.stringValue
            print("PLATED INVITE: picked \(name)")

            // The picker dismisses itself; this completion is the moment it
            // is genuinely off screen and the next thing may be presented.
            picker.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                Task { @MainActor in await self.compose() }
            }
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            picker.dismiss(animated: true) { [weak self] in
                self?.finish(.cancelled)
            }
        }

        @MainActor
        private func compose() async {
            let outcome = await prepare(phone)
            guard case .ready(let url) = outcome else {
                let reason: String
                if case .noAccount = outcome {
                    reason = "That number has no iCloud account, so the link won't reach them. Try another number, or add them by name."
                } else {
                    reason = "Sign in to iCloud to send an invite link."
                }
                print("PLATED INVITE: no link — \(reason)")
                finish(.noLink(name: name, reason: reason))
                return
            }

            guard MFMessageComposeViewController.canSendText(), let top = topViewController() else {
                print("PLATED INVITE: this device can't send messages")
                finish(.noLink(name: name, reason: "This iPhone can't send messages, so there's no way to hand them a link from here."))
                return
            }

            print("PLATED INVITE: link ready, opening the composer")
            let composer = MFMessageComposeViewController()
            composer.recipients = [phone].compactMap { $0 }
            composer.body = Invitation.body(hostName: hostName, link: url)
            composer.messageComposeDelegate = self
            top.present(composer, animated: true)
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            let sent = result == .sent
            print("PLATED INVITE: composer finished, sent = \(sent)")
            controller.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.finish(sent ? .sent(name: self.name, phone: self.phone)
                                 : .notSent(name: self.name, phone: self.phone))
            }
        }

        private func finish(_ result: Result) {
            completion(result)
            // Delegate callbacks arrive nonisolated; the retain lives on the
            // main actor with everything else that touches presentation.
            Task { @MainActor in InviteFlow.retained = nil }
        }
    }

    /// The controller anything new must be presented on — the deepest one,
    /// since this flow always runs with at least one sheet already up.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? scene?.windows.first?.rootViewController
        else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
