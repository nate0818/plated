import SwiftUI

/// Launch follows app readiness. The canvas-and-type lockup has no timed gate.
struct LaunchOpenerView: View {
    let ready: Bool
    let onFinished: () -> Void
    @State private var finished = false

    var body: some View {
        Color.canvas
            .ignoresSafeArea()
        .task(id: ready) {
            guard ready, !finished else { return }
            finished = true
            onFinished()
        }
    }
}

#Preview { LaunchOpenerView(ready: false) {} }
