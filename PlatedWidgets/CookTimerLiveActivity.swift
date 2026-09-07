import ActivityKit
import WidgetKit
import SwiftUI

/// The cook timer on the Lock Screen and in the Dynamic Island.
///
/// The system counts down on its own from `endsAt`; the app sends nothing
/// while it runs. Past the finish the content is stale and the view says
/// so, until Cook Mode is opened again and takes it down. Quiet chrome:
/// canvas, ink, one tomato glyph. The dish is the content.
struct CookTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookTimerAttributes.self) { context in
            LockScreenTimer(context: context)
                .activityBackgroundTint(Plate.canvas)
                .activitySystemActionForegroundColor(Plate.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Plate.tomato)
                        Text(context.attributes.dish)
                            .font(.jakarta(15, "Bold"))
                            .foregroundStyle(Plate.ink)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(endsAt: context.state.endsAt, stale: context.isStale, size: 24)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(stepLine(context.attributes.step, stale: context.isStale))
                        .font(.jakarta(13, "SemiBold"))
                        .foregroundStyle(Plate.inkSecondary)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Plate.tomato)
            } compactTrailing: {
                TimerText(endsAt: context.state.endsAt, stale: context.isStale, size: 14)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Plate.tomato)
            }
        }
    }
}

private func stepLine(_ step: Int, stale: Bool) -> String {
    if stale { return "Time's up. Open Plated to clear it." }
    return step > 0 ? "Step \(step)" : "Timer"
}

/// The countdown. `Text(timerInterval:)` is drawn by the system and never
/// needs an update from the app; past the finish it would count up, so
/// the stale view swaps in words instead.
private struct TimerText: View {
    let endsAt: Date
    let stale: Bool
    let size: CGFloat

    var body: some View {
        if stale || endsAt <= .now {
            Text("Done")
                .font(.jakarta(size, "Bold"))
                .foregroundStyle(Plate.tomato)
        } else {
            Text(timerInterval: Date.now...endsAt, countsDown: true)
                .font(.jakarta(size, "Bold"))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Plate.ink)
        }
    }
}

private struct LockScreenTimer: View {
    let context: ActivityViewContext<CookTimerAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(Plate.fill).frame(width: 44, height: 44)
                Image(systemName: "timer")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Plate.tomato)
            }
            VStack(alignment: .leading, spacing: 3) {
                // The dish is content, so it wraps rather than truncates.
                Text(context.attributes.dish)
                    .font(.jakarta(17, "Bold"))
                    .foregroundStyle(Plate.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(stepLine(context.attributes.step, stale: context.isStale))
                    .font(.jakarta(13, "SemiBold"))
                    .foregroundStyle(Plate.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 10)
            // A fixed track for the digits. `Text(timerInterval:)` asks for
            // the width of its longest possible reading, and left to size
            // itself it pushed the dish clean off the platter.
            TimerText(endsAt: context.state.endsAt, stale: context.isStale, size: 26)
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
