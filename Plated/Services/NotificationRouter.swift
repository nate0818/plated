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
        /// A night planned, or an edit that lost: both open the plan.
        static let household = "plated.category.household"
        /// A seat joined or left. The placeholder has to name the same
        /// door the tap opens, so these keep their own category rather
        /// than borrowing the plan's sentence on a locked screen.
        static let householdSeat = "plated.category.household.seat"
        /// A recipe added, which opens the cookbook.
        static let householdRecipe = "plated.category.household.recipe"
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
        // The same category the cook reminders wear: a tap lands on the
        // plan, and there is nothing to plate or answer about a night.
        case .plan: return Category.plan
        case .householdSeat, .householdLeft: return Category.householdSeat
        case .recipe: return Category.householdRecipe
        case .conflict: return Category.household
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
            category(Category.cook, [], "Time to check the pan."),
            category(Category.household, [], "Open the plan."),
            category(Category.householdSeat, [], "Open Home."),
            category(Category.householdRecipe, [], "Open the cookbook.")
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
        let (openPost, feedVisible, activityVisible, planVisible, householdVisible, cookbookVisible) = await MainActor.run {
            (Presence.shared.openPost, Presence.shared.feedVisible,
             Presence.shared.activityVisible, Presence.shared.planVisible,
             Presence.shared.householdVisible, Presence.shared.cookbookVisible)
        }
        let options = Self.presentation(
            post: post, kind: kind, openPost: openPost,
            feedVisible: feedVisible, activityVisible: activityVisible, planVisible: planVisible,
            householdVisible: householdVisible, cookbookVisible: cookbookVisible
        )
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
        post: String, kind: String, openPost: String?, feedVisible: Bool,
        activityVisible: Bool = false, planVisible: Bool = false,
        householdVisible: Bool = false, cookbookVisible: Bool = false
    ) -> UNNotificationPresentationOptions {
        // The bell list is the one screen where every notice is already
        // in front of the person; a banner over it announced the row
        // that had just appeared underneath.
        let looking = (!post.isEmpty && openPost == post)
            || (feedVisible && (kind == "dish" || kind == "ask" || kind == "more"))
            || (activityVisible && !kind.isEmpty)
            || (planVisible && kind == "plan")
            // The household's own two, which were the only notices in the
            // app whose destination nobody was watching: a join banner
            // landed over the roster it had just been added to, and a recipe
            // banner over the cookbook row underneath it.
            || (householdVisible && (kind == "householdSeat" || kind == "householdLeft"))
            || (cookbookVisible && kind == "recipe")
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

    static let dayRequested = Notification.Name("plated.link.day")
    private static var pendingDay: Date?

    /// A night on the plan. The shell selects Plan; the week moves to it.
    static func request(day: Date) {
        pendingDay = day
        NotificationCenter.default.post(name: dayRequested, object: nil)
    }

    static func takeDay() -> Date? {
        defer { pendingDay = nil }
        return pendingDay
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
    /// The bell's own list, which draws every row a banner would repeat.
    var activityVisible = false
    /// The week itself. A banner about a night while the week is in front
    /// announces the row that just appeared on it.
    var planVisible = false
    /// The household screen, which is where a seat joining or leaving opens
    /// and where the roster it is about is already drawn.
    var householdVisible = false
    /// The cookbook, for the same reason: a recipe joining it lands over the
    /// list that just gained the row.
    var cookbookVisible = false

    /// The shell says which tab is showing, and these two follow it.
    ///
    /// They were driven from `onAppear` and `onDisappear` on the tab roots,
    /// which is wrong under this shell: it is a `switch` on a selection and
    /// not a `TabView`, so a root that has been shown once is not torn down
    /// when another tab is chosen and its `onDisappear` does not fire. The
    /// flag latched true and every household banner for the rest of the
    /// session arrived silently, which is a worse failure than the one the
    /// flags were added to fix, because nothing on screen says it happened.
    ///
    /// The Table's feed and the week keep their own hooks: those are pushed
    /// and popped rather than switched, and they answer a finer question
    /// than which tab is showing.
    /// All four, not the two that were added last. `planVisible` and
    /// `feedVisible` were driven from `onAppear`/`onDisappear` on their own
    /// tab roots and latch for exactly the same reason: this shell is a
    /// switch on a selection, so a root shown once is never torn down. The
    /// fix went to the two flags in front of me and was reported as a class,
    /// which is the shape that has cost this branch more than any other.
    ///
    /// The screens keep their own hooks as well, and the two compose rather
    /// than fight: a tab change is the coarse answer and runs here, while a
    /// push inside a tab is the fine one and runs there.
    static func follow(_ tab: AppTab) {
        shared.householdVisible = tab == .home
        shared.cookbookVisible = tab == .cookbook
        shared.planVisible = tab == .week
        shared.feedVisible = tab == .table
    }
}
