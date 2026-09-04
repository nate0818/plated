import SwiftUI
import SwiftData

/// The bell. Activity is one tap away from every tab — the badge counts
/// what's unread, and the same bell reads the same everywhere.
struct ActivityBellButton: View {
    var size: CGFloat = 38
    var accessibilityID = "notifications-bell"
    let action: () -> Void

    @Query(filter: #Predicate<PlatedNotification> { !$0.isRead })
    private var unread: [PlatedNotification]

    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Circle()
                .strokeBorder(Color.hairline, lineWidth: 1.5)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: unread.isEmpty ? "bell" : "bell.fill")
                        .font(.system(size: size >= 44 ? 18 : 15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .contentTransition(.symbolEffect(.replace))
                }
                .overlay(alignment: .topTrailing) {
                    if !unread.isEmpty {
                        Text(unread.count > 9 ? "9+" : "\(unread.count)")
                            .plType(.micro, .extraBold)
                            .foregroundStyle(Color.onTomato)
                            .contentTransition(.numericText())
                            .padding(.horizontal, 4)
                            // Floored, not fixed: this held 32pt digits in
                            // a 16pt capsule at AX5 and rendered as a red
                            // smear. plChrome below stops the growth; the
                            // floor stops the clip.
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.tomato, in: Capsule())
                            .offset(x: -1, y: 3)
                            .transition(.plArrive)
                    }
                }
                // News lands with a pop, counts tick, read-all fades out.
                .animation(.plPop, value: unread.count)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .plChrome()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Notifications")
        .accessibilityValue(unread.isEmpty ? "No unread notifications" : "\(unread.count) unread \(unread.count == 1 ? "notification" : "notifications")")
        .accessibilityHint("Shows activity at your table")
        .accessibilityIdentifier(accessibilityID)
    }
}
