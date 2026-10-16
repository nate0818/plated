import Foundation

/// Transient wheel state stays local; the dinner plan changes only at rest.
/// Programmatic navigation cancels a scrub so an old deceleration cannot win.
struct DateWheelInteraction {
    enum Activity: Equatable { case idle, scrubbing, navigating }
    private(set) var activity: Activity = .idle
    private(set) var previewDate: Date?
    private(set) var feedbackRevision = 0
    private var lastFeedbackTime: TimeInterval?

    mutating func begin(at date: Date) {
        activity = .scrubbing
        previewDate = date
        lastFeedbackTime = nil
    }

    mutating func cross(to date: Date, at time: TimeInterval) {
        guard activity == .scrubbing, previewDate != date else { return }
        previewDate = date
        // Preserve individual detents at normal speed without buzzing on a fling.
        if lastFeedbackTime.map({ time - $0 >= 0.045 }) ?? true {
            feedbackRevision &+= 1
            lastFeedbackTime = time
        }
    }

    mutating func settle(on date: Date, at time: TimeInterval) -> Date? {
        guard activity == .scrubbing else { return nil }
        cross(to: date, at: time)
        cancel()
        return date
    }

    mutating func navigate(to date: Date, feedback: Bool) {
        activity = .navigating
        previewDate = date
        lastFeedbackTime = nil
        if feedback { feedbackRevision &+= 1 }
    }

    mutating func cancel() {
        activity = .idle
        previewDate = nil
        lastFeedbackTime = nil
    }

    static func centeredIndex(offset: CGFloat, leadingInset: CGFloat, stride: CGFloat, count: Int) -> Int? {
        guard count > 0, stride > 0, offset.isFinite, leadingInset.isFinite, stride.isFinite else { return nil }
        let index = ((offset + leadingInset) / stride).rounded()
        return Int(min(max(index, 0), CGFloat(count - 1)))
    }
}
