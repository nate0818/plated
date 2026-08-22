import SwiftUI
import SwiftData

/// The bell. Activity is one tap away from every tab — the badge counts
/// what's unread, and the same bell reads the same everywhere.
struct ActivityBellButton: View {
    var size: CGFloat = 38
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
                    Image(systemName: "bell")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
                .overlay(alignment: .topTrailing) {
                    if !unread.isEmpty {
                        Text("\(min(unread.count, 9))")
                            .font(.jakarta(9, .extraBold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Color.tomato, in: Circle())
                            .offset(x: -1, y: 3)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
