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
///
/// One flow, two rooms (docs/household.md §6, §9): `kind` decides which
/// link is minted and which sentence goes round it, and the composer's
/// answer travels back with what was minted so the caller records exactly
/// the seat or entry the message named.
@MainActor
enum InviteFlow {

    enum Result {
        /// They picked somebody and the message actually sent.
        case sent(name: String, phone: String?, prepared: Seats.Prepared)
        /// Picked somebody, but nothing was sent — cancelled, or failed.
        case notSent(name: String, phone: String?, prepared: Seats.Prepared)
        /// Never got as far as a person.
        case cancelled
        /// A person, but no link to give them, so nothing was offered.
        case noLink(name: String, reason: String)
    }

    /// Somebody already chosen, so the picker is skipped: onboarding's
    /// shortlist names the person beside the verb, and a second picker on
    /// top of that would be asking who twice.
    struct Recipient {
        var name: String
        var phone: String?
    }

    /// Present the picker, then the composer, then report what happened.
    /// `prepare` is the link-minting step, run between the two while nothing
    /// is on screen.
    static func run(
        kind: Seats.Kind,
        hostName: String,
        to recipient: Recipient? = nil,
        prepare: @escaping () async -> Seats.Prepared,
        completion: @escaping (Result) -> Void
    ) {
        // The picker path is a screen of its own and cannot be tapped twice.
        // The recipient path is a row in a list: a second tap while the first
        // is still minting would present a second composer over the first and
        // race two share mints, so it is refused rather than queued.
        if recipient != nil, isBusy {
            print("PLATED INVITE: an invitation is already in flight")
            completion(.cancelled)
            return
        }
        let delegate = PickerDelegate(kind: kind, hostName: hostName, prepare: prepare, completion: completion)
        // The delegate must outlive this call — CNContactPicker holds its
        // delegate weakly, and a local would be gone before the first tap.
        inFlight[ObjectIdentifier(delegate)] = delegate

        if let recipient {
            delegate.chose(name: recipient.name, phone: recipient.phone)
            Task { @MainActor in await delegate.compose() }
            return
        }
        guard let top = topViewController() else {
            inFlight[ObjectIdentifier(delegate)] = nil
            completion(.cancelled)
            return
        }
        let picker = CNContactPickerViewController()
        picker.delegate = delegate
        // Somebody with no number cannot be sent an invitation.
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        top.present(picker, animated: true)
    }

    /// The system share sheet over whatever is on screen, for a link handed
    /// over by any road but Messages. Same UIKit door as the composer, for
    /// the same reason: it has to land on top of a sheet that is already up.
    static func share(_ url: URL, message: String, from anchor: UIView? = nil) {
        guard let top = topViewController() else { return }
        let sheet = UIActivityViewController(activityItems: [message, url], applicationActivities: nil)
        // iPad presents this as a popover and raises an uncaught exception at
        // presentation time when it has nothing to point at, which killed the
        // app on the tap after the household share had just been minted. The
        // app ships to "1,2", so this is not a hypothetical device.
        if let pop = sheet.popoverPresentationController {
            if let anchor {
                pop.sourceView = anchor
                pop.sourceRect = anchor.bounds
            } else {
                pop.sourceView = top.view
                pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                pop.permittedArrowDirections = []
            }
        }
        top.present(sheet, animated: true)
    }

    /// Every delegate with something still on screen, and the only strong
    /// reference to it. A single slot meant a second Invite tap replaced the
    /// first delegate while its composer was still up: UIKit holds a message
    /// composer's delegate weakly, so Cancel and Send called nothing, the
    /// sheet never dismissed, and the `.sent` that lays the seat was lost.
    private static var inFlight: [ObjectIdentifier: AnyObject] = [:]

    /// True while any invitation is still minting or on screen.
    static var isBusy: Bool { !inFlight.isEmpty }

    private final class PickerDelegate: NSObject, CNContactPickerDelegate, MFMessageComposeViewControllerDelegate {
        private let kind: Seats.Kind
        private let hostName: String
        private let prepare: () async -> Seats.Prepared
        private let completion: (Result) -> Void
        private var name = ""
        private var phone: String?

        init(
            kind: Seats.Kind,
            hostName: String,
            prepare: @escaping () async -> Seats.Prepared,
            completion: @escaping (Result) -> Void
        ) {
            self.kind = kind
            self.hostName = hostName
            self.prepare = prepare
            self.completion = completion
        }

        func chose(name: String, phone: String?) {
            self.name = name
            self.phone = phone
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let full = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            chose(name: full.isEmpty ? contact.nickname : full,
                  phone: contact.phoneNumbers.first?.value.stringValue)
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
        func compose() async {
            // Asked before `prepare`, not after. Minting is not a read: on
            // the first invitation it saves the zone, the root, both shares
            // and runs `publishAll`, so asking afterwards published a whole
            // household for a message this phone was never going to send.
            guard MFMessageComposeViewController.canSendText() else {
                print("PLATED INVITE: this device can't send messages")
                finish(.noLink(name: name, reason: "This iPhone can't send messages, so there's no way to hand them a link from here."))
                return
            }

            let prepared = await prepare()
            guard case .ready(let url) = prepared.outcome else {
                let reason: String
                if case .noAccount = prepared.outcome {
                    reason = "That number has no iCloud account, so the link won't reach them. Try another number, or add them by name."
                } else {
                    // Not always "sign in to iCloud": a member never mints a
                    // household link, and a slow network is not a signed-out
                    // account. Seats owns the one sentence for all of them.
                    reason = Seats.noLinkReason(prepared)
                }
                print("PLATED INVITE: no link — \(reason)")
                finish(.noLink(name: name, reason: reason))
                return
            }

            guard let top = topViewController() else {
                finish(.notSent(name: name, phone: phone, prepared: prepared))
                return
            }

            print("PLATED INVITE: \(kind.rawValue) link ready, opening the composer")
            let composer = MFMessageComposeViewController()
            composer.recipients = [phone].compactMap { $0 }
            composer.body = Invitation.body(hostName: hostName, kind: kind, link: url)
            composer.messageComposeDelegate = self
            pending = prepared
            top.present(composer, animated: true)
        }

        /// What the open composer is carrying, so the answer can name it.
        private var pending = Seats.Prepared.noCloud

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            let sent = result == .sent
            print("PLATED INVITE: composer finished, sent = \(sent)")
            controller.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.finish(sent ? .sent(name: self.name, phone: self.phone, prepared: self.pending)
                                 : .notSent(name: self.name, phone: self.phone, prepared: self.pending))
            }
        }

        private func finish(_ result: Result) {
            // Delegate callbacks arrive nonisolated; the retain lives on the
            // main actor with everything else that touches presentation. The
            // retain is dropped BEFORE the answer goes out, so a caller that
            // re-enables its button on the answer is not refused by a flow
            // that has already finished.
            let key = ObjectIdentifier(self)
            let completion = self.completion
            Task { @MainActor in
                InviteFlow.inFlight[key] = nil
                completion(result)
            }
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
