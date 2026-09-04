import SwiftUI
import UIKit

/// Native sheets keep their drag-to-dismiss behavior and gain a background
/// tap exit. Draft-protected sheets (isModalInPresentation) remain protected.
private struct OutsideSheetTap: UIViewControllerRepresentable {
    let dismiss: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller(dismiss: dismiss) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.dismissSheet = dismiss }
    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        var dismissSheet: () -> Void
        private weak var container: UIView?
        private weak var host: UIViewController?
        private var tap: UITapGestureRecognizer?
        init(dismiss: @escaping () -> Void) { dismissSheet = dismiss; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            var owner: UIViewController = self
            while let parent = owner.parent { owner = parent }
            guard let container = owner.presentationController?.containerView else { return }
            if self.container === container { return }
            detach()
            host = owner
            self.container = container
            let tap = UITapGestureRecognizer(target: self, action: #selector(outside))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            container.addGestureRecognizer(tap)
            self.tap = tap
        }
        override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); detach() }
        private func detach() { if let tap { container?.removeGestureRecognizer(tap) }; tap = nil; container = nil }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let host, !host.isModalInPresentation, host.presentedViewController == nil,
                  let presentation = host.presentationController, let container else { return false }
            return !presentation.frameOfPresentedViewInContainerView.contains(gestureRecognizer.location(in: container))
        }
        @objc private func outside() { dismissSheet() }
    }
}
private struct TapOutsideSheetModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View { content.background(OutsideSheetTap { dismiss() }.frame(width: 0, height: 0)) }
}
extension View {
    func plTapOutsideToDismiss() -> some View { modifier(TapOutsideSheetModifier()) }
}
