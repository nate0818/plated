import Foundation
import UserNotifications
import UIKit

/// What happens when a notification is on screen, or tapped.
///
/// One delegate for every notification the app raises, installed before the
/// app finishes launching: a tap on a banner that cold-starts the app is
/// delivered to whatever delegate exists at that moment, and a delegate
/// installed a beat later never hears about it. That is the one ordering
/// rule in this file and it is the reason `install()` is called from
/// `ShareAcceptor.application(_:didFinishLaunchingWithOptions:)` and from
/// nowhere else.
///
/// Three jobs. **Presenting**: a banner about the post somebody is reading
/// is dropped, because the thread in front of them already shows the new
/// comment (see `Presence`). **Routing**: every notice carries a
/// `plated://` link, and a tap opens the thing the notice was about, which
/// is the same continuity rule the app applies to a tile. **Acting**:
/// "Plate it" and "Reply" do the thing without opening the app, through the
/// same road a tap in the feed would take.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationRouter()

    enum Key {
        static let link = "link"
        static let post = "post"
        static let kind = "kind"
        /// The person the notice is about, full name, so a reply from the
        /// banner is addressed to them and not to whoever owns the dish.
        static let actor = "actor"
    }

    enum Category {
        static let dish = "plated.category.dish"
        /// A question is answered, not plated.
        static let ask = "plated.category.ask"
        static let comment = "plated.category.comment"
        static let plates = "plated.category.plates"
        static let turnMine = "plated.category.turn.mine"
        static let plan = "plated.category.plan"
        static let cook = "plated.category.cook"
    }

    enum Action {
        static let plate = "plated.action.plate"
        static let reply = "plated.action.reply"
        static let grocery = "plated.action.grocery"
    }

    static func category(for kind: TableNews.Notice.Kind) -> String {
        switch kind {
        case .dish: return Category.dish
        case .ask: return Category.ask
        case .comment: return Category.comment
        case .plates, .kiss, .votes, .seat, .more: return Category.plates
        }
    }

    @MainActor
    static func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared

        // Verbs that name outcomes, same as a button. The system draws
        // them; the copy is ours.
        let plate = UNNotificationAction(
            identifier: Action.plate, title: "Plate it", options: []
        )
        let reply = UNTextInputNotificationAction(
            identifier: Action.reply, title: "Reply", options: [],
            textInputButtonTitle: "Send", textInputPlaceholder: "Write back"
        )
        let grocery = UNNotificationAction(
            identifier: Action.grocery, title: "Open the grocery list", options: [.foreground]
        )
        // With Show Previews set to When Unlocked, the default on every
        // Face ID phone, a locked screen shows only what the category
        // allows. Without these it read "Plated: Notification" for
        // everything, which is the doorbell the register forbids. The
        // title is the person and the deed; the body waits for the unlock.
        let reveal: UNNotificationCategoryOptions = [.hiddenPreviewsShowTitle, .hiddenPreviewsShowSubtitle]
        func category(_ id: String, _ actions: [UNNotificationAction], _ placeholder: String) -> UNNotificationCategory {
            UNNotificationCategory(
                identifier: id, actions: actions, intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: placeholder, options: reveal
            )
        }
        center.setNotificationCategories([
            category(Category.dish, [plate], "Open to see it."),
            category(Category.ask, [], "Open to answer."),
            category(Category.comment, [reply], "Open to read it."),
            category(Category.plates, [], "Open the dish."),
            category(Category.turnMine, [grocery], "Open the plan."),
            category(Category.plan, [], "Open the plan."),
            category(Category.cook, [], "Time to check the pan.")
        ])
    }

    // MARK: On screen

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        let post = info[Key.post] as? String ?? ""
        let kind = info[Key.kind] as? String ?? ""
        // Only ever called while the app is in front, so "are they looking
        // at it" is a question about which screen, never about app state.
        let (openPost, feedVisible) = await MainActor.run {
            (Presence.shared.openPost, Presence.shared.feedVisible)
        }
        let options = Self.presentation(post: post, kind: kind, openPost: openPost, feedVisible: feedVisible)
        if options == [.list] {
            print("[Notify] kept a banner about what is on screen to the list (\(kind))")
        } else {
            print("[Notify] presenting \(kind.isEmpty ? "a reminder" : kind) in front")
        }
        return options
    }

    /// What to draw for a notice arriving while the app is in front. Pure,
    /// so a test can hold it to the rule. No banner and no sound over the
    /// thing itself, but it still goes in the list: a sheet over the feed
    /// counts as "looking" here, and a notice that vanished because
    /// somebody was mid-way through writing a post would be a notice that
    /// never happened.
    static func presentation(
        post: String, kind: String, openPost: String?, feedVisible: Bool
    ) -> UNNotificationPresentationOptions {
        let looking = (!post.isEmpty && openPost == post)
            || (feedVisible && (kind == "dish" || kind == "ask" || kind == "more"))
        return looking ? [.list] : [.banner, .list, .sound]
    }

    // MARK: Tapped

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let post = info[Key.post] as? String ?? ""
        print("[Notify] response \(response.actionIdentifier) post=\(post)")
        switch response.actionIdentifier {
        case Action.plate:
            await MainActor.run { Haptic.plate() }
            await TableNews.plate(post: post, context: PlatedStore.shared.mainContext)
        case Action.reply:
            let text = (response as? UNTextInputNotificationResponse)?.userText ?? ""
            let actor = info[Key.actor] as? String ?? ""
            await TableNews.reply(post: post, to: actor, text: text, context: PlatedStore.shared.mainContext)
        case Action.grocery:
            await MainActor.run { LinkRelay.open(DeepLink.url(.grocery)) }
        default:
            // The default tap, and a dismissed banner: the first opens what
            // the notice was about, the second is nothing to act on.
            guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
                  let raw = info[Key.link] as? String, let url = URL(string: raw)
            else { return }
            await MainActor.run { LinkRelay.open(url) }
        }
    }
}

/// A link on its way to the shell.
///
/// `onOpenURL` is the shell's one door for `plated://`, and nothing outside
/// SwiftUI can knock on it. A notification tap arrives at a UIKit delegate,
/// often before the shell exists at all, so the URL is parked here and the
/// shell collects it when it can: on the next `opened` post if it is
/// already on screen, on its own `onAppear` if it is not.
@MainActor
enum LinkRelay {
    static let opened = Notification.Name("plated.link.opened")
    private static var pending: URL?

    static func open(_ url: URL) {
        pending = url
        NotificationCenter.default.post(name: opened, object: nil)
    }

    static func take() -> URL? {
        defer { pending = nil }
        return pending
    }

    // The second leg. The shell selects the tab; the tab opens the thing.
    // Same parking arrangement, because the tab's view may not exist yet
    // either.

    static let postRequested = Notification.Name("plated.link.post")
    private static var pendingPost: String?

    static func request(post record: String) {
        pendingPost = record
        NotificationCenter.default.post(name: postRequested, object: nil)
    }

    static func takePost() -> String? {
        defer { pendingPost = nil }
        return pendingPost
    }

    static let activityRequested = Notification.Name("plated.link.activity")
    private static var pendingActivity = false

    static func requestActivity() {
        pendingActivity = true
        NotificationCenter.default.post(name: activityRequested, object: nil)
    }

    static func takeActivity() -> Bool {
        defer { pendingActivity = false }
        return pendingActivity
    }
}

/// What is on screen right now, for the one decision that needs it.
///
/// Written by the Table's feed and thread on appear and disappear, read by
/// `NotificationRouter.willPresent`. Deliberately not `applicationState`:
/// that answers "is the app in front", which the delegate already knows,
/// and it is falsified by any system alert. The question is which screen.
@MainActor
final class Presence {
    static let shared = Presence()
    var feedVisible = false
    var openPost: String?
}
