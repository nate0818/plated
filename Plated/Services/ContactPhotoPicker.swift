import ContactsUI
import UIKit

/// Opens Apple's single-contact picker; no blanket address-book permission.
/// iOS does not expose the user's Me card or Apple ID photo automatically.
@MainActor
enum ContactPhotoPicker {
    private static var retained: Delegate?
    static func choose(completion: @escaping (Data?) -> Void) {
        guard retained == nil else { return }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var host = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = host?.presentedViewController { host = presented }
        guard let host else { completion(nil); return }
        let picker = CNContactPickerViewController()
        let delegate = Delegate(completion: completion)
        retained = delegate
        picker.delegate = delegate
        picker.predicateForEnablingContact = NSPredicate(format: "imageDataAvailable == YES")
        picker.predicateForSelectionOfContact = NSPredicate(value: true)
        host.present(picker, animated: true)
    }
    private final class Delegate: NSObject, CNContactPickerDelegate {
        let completion: (Data?) -> Void
        init(completion: @escaping (Data?) -> Void) { self.completion = completion }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let raw = (contact.isKeyAvailable(CNContactImageDataKey) ? contact.imageData : nil)
                ?? (contact.isKeyAvailable(CNContactThumbnailImageDataKey) ? contact.thumbnailImageData : nil)
            print("PLATED PROFILE: selected contact photo \(raw == nil ? "unavailable" : "available")")
            picker.dismiss(animated: true) {
                self.completion(raw.flatMap(ProfilePhoto.square))
                retained = nil
            }
        }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            picker.dismiss(animated: true) { self.completion(nil); retained = nil }
        }
    }
}
