import SwiftUI
import SwiftData

/// The bell. Activity is one tap away from every tab — the badge counts
/// what's unread, and the same bell reads the same everywhere.
struct ActivityBellButton: View {
    var size: CGFloat = 38
    var accessibilityID = "notifications-bell"
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentSafety = ContentSafety.shared

    @Query(filter: #Predicate<PlatedNotification> { !$0.isRead })
    private var unread: [PlatedNotification]

    private var visibleUnread: [PlatedNotification] {
        unread.filter { !contentSafety.hidesTableActivity($0) }
    }

    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Circle()
                .fill(Color.clear)
                .frame(width: size, height: size)
                .overlay {
                    ActivityBellGlyph(
                        size: size,
                        isUnread: !visibleUnread.isEmpty,
                        reduceMotion: reduceMotion,
                        trigger: visibleUnread.count
                    )
                }
                .overlay(alignment: .topTrailing) {
                    ActivityBellBadge(count: visibleUnread.count)
                }
                // News lands with a pop, counts tick, read-all fades out.
                .animation(.plPop, value: visibleUnread.count)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .plChrome()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Notifications")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows activity at your table")
        .accessibilityIdentifier(accessibilityID)
    }

    private var accessibilityValue: String {
        guard !visibleUnread.isEmpty else { return "No unread notifications" }
        let noun = visibleUnread.count == 1 ? "notification" : "notifications"
        return "\(visibleUnread.count) unread \(noun)"
    }
}

private struct ActivityBellGlyph: View {
    let size: CGFloat
    let isUnread: Bool
    let reduceMotion: Bool
    let trigger: Int

    var body: some View {
        KeyframeAnimator(initialValue: Double.zero, trigger: trigger) { (angle: Double) in
            Image(systemName: isUnread ? "bell.fill" : "bell")
                .font(.system(size: size >= 44 ? 18 : 15, weight: .semibold))
                .foregroundStyle(Color.ink)
                .contentTransition(.symbolEffect(.replace))
                .rotationEffect(.degrees(reduceMotion ? 0 : angle), anchor: .top)
        } keyframes: { (_: Double) in
            KeyframeTrack {
                MoveKeyframe<Double>(0)
                CubicKeyframe<Double>(-11, duration: 0.11)
                CubicKeyframe<Double>(9, duration: 0.12)
                CubicKeyframe<Double>(-5, duration: 0.10)
                CubicKeyframe<Double>(0, duration: 0.12)
            }
        }
    }
}

private struct ActivityBellBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 9 ? "9+" : "\(count)")
                .plType(.micro, .extraBold)
                .plActionLabel()
                .foregroundStyle(Color.onOlive)
                .contentTransition(.numericText())
                .padding(.horizontal, 4)
                // Floored, not fixed: this held 32pt digits in a 16pt capsule
                // at AX5 and rendered as a red smear. plChrome stops the
                // growth; the floor stops the clip.
                .frame(minWidth: 16, minHeight: 16)
                .background(Color.olive, in: Radius.shape(Radius.chip))
                .overlay(Radius.shape(Radius.chip).strokeBorder(Color.canvas, lineWidth: 2))
                .shadow(color: Color.olive.opacity(0.22), radius: 5, y: 2)
                .offset(x: 2, y: -2)
                .transition(.plArrive)
        }
    }
}
