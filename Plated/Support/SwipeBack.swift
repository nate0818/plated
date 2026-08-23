import SwiftUI
import UIKit

/// Every pushed screen in Plated hides the system navigation bar and draws
/// its own chevron — which is precisely the condition under which UIKit
/// switches `interactivePopGestureRecognizer` off. Quiet chrome was never
/// meant to cost the edge swipe: nobody reaches the top-left corner of a
/// 6.9" phone one-handed, and the gesture is the real back button.
///
/// So we hand the recognizer a delegate of our own and turn it back on.
/// Attach with `.plSwipeBack()` on any screen that hides the bar. It is
/// idempotent — a stack whose root and detail both ask for it simply sets
/// the same rule twice.
extension View {
    func plSwipeBack() -> some View {
        background(
            SwipeBackEnabler()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}

/// One rule: the edge pan may begin whenever there is a screen underneath to
/// go back to. Letting it run at the root is the classic way to wedge a
/// navigation controller into a state where nothing responds again.
///
/// Internal rather than file-private so the predicate can be exercised
/// directly — UIKit will not call a delegate without a real finger, and the
/// simulator cannot inject one, so this is the only part of the gesture with
/// logic in it that can be proven.
final class PopGestureRule: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let nav = navigationController else { return false }
        return nav.viewControllers.count > 1 && nav.transitionCoordinator == nil
    }
}

/// A zero-size child controller whose only job is to find the navigation
/// controller SwiftUI built for us and fix its recognizer. It holds the rule
/// strongly because the recognizer's `delegate` is weak; as long as the
/// screen is on the stack, so is the gesture.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Host() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    private final class Host: UIViewController {
        private let rule = PopGestureRule()

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            adopt()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // `didMove` can land before the hosting controller is on the
            // stack; by the time we appear, the nav controller is real.
            adopt()
        }

        private func adopt() {
            guard let nav = navigationController else { return }
            rule.navigationController = nav
            nav.interactivePopGestureRecognizer?.delegate = rule
            nav.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
