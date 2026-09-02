import Foundation
import UIKit

/// A person's face, sized for a circle.
///
/// **On the Apple ID photo, plainly.** It cannot be read. Sign in with Apple
/// hands back exactly nine things and not one of them is an image:
/// `user`, `state`, `authorizedScopes`, `authorizationCode`, `identityToken`,
/// `email`, `fullName`, `realUserStatus`, `userAgeRange`. There is no photo
/// property anywhere in AuthenticationServices. The picture you see in the
/// sign-in sheet is drawn by the system, inside its own process, and is never
/// vended to the app. Contacts is not a back door either: the "me" card API,
/// `unifiedMeContactWithKeysToFetch`, is marked `NS_AVAILABLE(10_11, NA)` —
/// macOS only, unavailable on iOS. CloudKit's `CKUserIdentity` carries a name
/// and a lookup info, no image.
///
/// So the honest goal is not "get the Apple photo". It is: never let a first
/// run end with a letter in a circle where a face belongs. That is a design
/// problem, and the answer is to ask for the photo at the moment the person
/// is already telling us who they are, in one tap, with their library and
/// camera both one tap away.
enum ProfilePhoto {

    /// The side of the stored square, in pixels. An avatar is never drawn
    /// bigger than about 140pt, so 400 covers a 3x screen with room to spare
    /// and still lands in single-digit kilobytes. These rows sync, so every
    /// byte is a byte of somebody's iCloud.
    private static let side: CGFloat = 400

    /// Centre-cropped to a square and recompressed.
    ///
    /// Cropped here rather than at draw time because the avatar is a circle
    /// in two dozen places and `scaledToFill` inside a clipped circle throws
    /// away the same pixels every time it renders. Do it once, store the
    /// result, and every avatar in the app gets the cheap path.
    static func square(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let shortest = min(image.size.width, image.size.height)
        guard shortest > 0 else { return nil }

        let crop = CGRect(
            x: (image.size.width - shortest) / 2,
            y: (image.size.height - shortest) / 2,
            width: shortest,
            height: shortest
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let target = CGSize(width: side, height: side)
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            // Draw the source shifted so the centre square lands on the
            // canvas, then let the renderer scale it down.
            let scale = side / shortest
            image.draw(in: CGRect(
                x: -crop.origin.x * scale,
                y: -crop.origin.y * scale,
                width: image.size.width * scale,
                height: image.size.height * scale
            ))
        }
        return rendered.jpegData(compressionQuality: 0.8)
    }

    // MARK: The hand-off between onboarding and the table

    /// Where a photo waits between "you chose it" and "there is a row to put
    /// it on".
    ///
    /// Onboarding asks for the face before the head of the table exists:
    /// the owner row is written on the way out of the contacts step on a
    /// device, and by the sample seed on a simulator. Rather than teach the
    /// photo step to create a member (and race the seed's `isEmpty` check
    /// into skipping every sample recipe), it parks the bytes and the shell
    /// hangs them on the owner the first time it sees one.
    private static let pendingKey = "pendingProfilePhoto"

    static func park(_ data: Data?) {
        guard let data else {
            UserDefaults.standard.removeObject(forKey: pendingKey)
            return
        }
        UserDefaults.standard.set(data, forKey: pendingKey)
    }

    static var parked: Data? {
        let data = UserDefaults.standard.data(forKey: pendingKey)
        return (data?.isEmpty ?? true) ? nil : data
    }

    static func clearParked() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }
}
