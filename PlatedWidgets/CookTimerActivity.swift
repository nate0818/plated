import ActivityKit
import Foundation

// IDENTICAL COPY in PlatedWidgets/CookTimerActivity.swift. ActivityKit pairs
// the app's request with the widget's view by this type, and the widget
// target cannot import the app, so the file is hand-copied and
// scripts/check-tokens refuses a build where the two differ. Change this
// one, then copy it across.

/// The one running cook timer, as the Lock Screen and the Dynamic Island
/// draw it. Static: which dish and which step. Dynamic: when it ends, which
/// the system counts down on its own with no update from the app.
struct CookTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
    }

    var dish: String
    /// One-based, for "Step 3". Zero when the timer was started outside a step.
    var step: Int
}
