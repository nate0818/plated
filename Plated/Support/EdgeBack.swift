import SwiftUI
import UIKit

/// A left-edge swipe that steps back through the tabs you have been on.
///
/// **Why the app needs one.** `plSwipeBack` restores the edge gesture on
/// PUSHED screens, and that half has always worked. But the four tabs are a
/// plain `switch` inside a `ZStack`, not a stack, so at a tab's root there is
/// nothing for UIKit to pop and no gesture at all. Land on Table from Plan
/// and the only way out is to hit a 68pt bar at the bottom of a 6.9" phone,
/// which is the exact reach problem the edge swipe exists to solve. The
/// gesture is the back button on a big phone; a tab bar does not excuse its
/// absence.
///
/// **Why a UIKit edge recogniser and not a SwiftUI `DragGesture`.** Every tab
/// is full of horizontal scrollers: filter chips on Recipes, the photo strip
/// in the editor, the day rail on Plan, `SwipeRow`'s own drag on the week.
/// A `DragGesture` spanning the screen fights all of them and either steals
/// their touches or loses its own. `UIScreenEdgePanGestureRecognizer` claims
/// only the first few points in from the bezel, where no content lives, and
/// it is the same recogniser iOS itself uses, so it behaves the way a thumb
/// expects.
///
/// **What it refuses to do.** It never fires while a sheet is up, because a
/// sheet's own downward drag is the way out of a sheet, and it never fires
/// while a page is pushed, because that swipe belongs to the navigation
/// stack. The two gestures divide the edge cleanly instead of racing for it.
extension View {
    func plEdgeBack(perform action: @escaping () -> Void) -> some View {
        background(
            EdgeBackAttacher(action: action)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}

private struct EdgeBackAttacher: UIViewControllerRepresentable {
    var action: () -> Void

    func makeUIViewController(context: Context) -> EdgeBackHost {
        let host = EdgeBackHost()
        host.action = action
        return host
    }

    func updateUIViewController(_ host: EdgeBackHost, context: Context) {
        host.action = action
    }
}

/// Internal rather than private so the travel rule can be exercised directly.
/// The gesture itself does run under simulator injection (verified: a left
/// edge swipe switches tabs, and pops a pushed page when one is up), but a
/// pure predicate is still the part worth asserting on.
final class EdgeBackHost: UIViewController, UIGestureRecognizerDelegate {
    var action: () -> Void = {}
    private weak var attachedTo: UIWindow?
    private var recognizer: UIScreenEdgePanGestureRecognizer?

    /// A flick counts even when it is short; a slow drag has to travel. Same
    /// shape as UIKit's own pop, so the two feel like one gesture.
    static func completes(travel: CGFloat, velocity: CGFloat) -> Bool {
        travel > 60 || velocity > 400
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attach()
    }

    private func attach() {
        // The window, not this controller's own view: the view is a zero-size
        // background that occupies no part of the edge it is listening to.
        guard recognizer == nil, let window = view.window else { return }
        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handle))
        pan.edges = .left
        pan.delegate = self
        window.addGestureRecognizer(pan)
        recognizer = pan
        attachedTo = window
    }

    deinit {
        if let recognizer { attachedTo?.removeGestureRecognizer(recognizer) }
    }

    @objc private func handle(_ pan: UIScreenEdgePanGestureRecognizer) {
        guard pan.state == .ended else { return }
        guard Self.completes(
            travel: pan.translation(in: pan.view).x,
            velocity: pan.velocity(in: pan.view).x
        ) else { return }
        action()
    }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let root = view.window?.rootViewController else { return false }
        // A sheet is on top. Its own drag is the way out of it.
        //
        // Recursive, and it has to be: a sheet raised from inside a tab body
        // (seats, grocery, the recipe filter, the editor) is presented by a
        // DESCENDANT controller, so the root's own `presentedViewController`
        // is nil and the one-level check let the edge swipe change tabs
        // behind an open sheet.
        if Self.hasSheet(root) { return false }
        // A pushed page pops first. That edge belongs to the nav stack.
        return !Self.hasPushedPage(root)
    }

    func gestureRecognizer(
        _ gesture: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
    }

    private static func hasSheet(_ controller: UIViewController) -> Bool {
        if controller.presentedViewController != nil { return true }
        return controller.children.contains(where: hasSheet)
    }

    private static func hasPushedPage(_ controller: UIViewController) -> Bool {
        if let nav = controller as? UINavigationController, nav.viewControllers.count > 1 {
            return true
        }
        return controller.children.contains(where: hasPushedPage)
    }
}
