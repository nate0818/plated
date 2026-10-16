import SwiftUI

/// Launch follows app readiness. The canvas-and-type lockup has no timed gate.
struct LaunchOpenerView: View {
    let ready: Bool
    var brief = false
    let onFinished: () -> Void
    @State private var finished = false

    var body: some View {
        VStack(spacing: 14) {
            PlatedWordmark(size: 54)
            Text("A little more together.")
                .plType(.body)
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas.ignoresSafeArea())
        .task(id: ready) {
            guard ready, !finished else { return }
            finished = true
            onFinished()
        }
    }
}

#Preview { LaunchOpenerView(ready: false) {} }
