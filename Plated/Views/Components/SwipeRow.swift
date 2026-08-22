import SwiftUI

/// One thing a swipe can reveal. Tomato is reserved for the destructive
/// one — everything else stays ink, per the house rule about earned colour.
struct SwipeAction: Identifiable {
    let id = UUID()
    let symbol: String
    let label: String
    var destructive = false
    let perform: () -> Void

    static func remove(_ perform: @escaping () -> Void) -> SwipeAction {
        SwipeAction(symbol: "trash", label: "Remove", destructive: true, perform: perform)
    }

    static func message(_ perform: @escaping () -> Void) -> SwipeAction {
        SwipeAction(symbol: "bubble.right", label: "Message", perform: perform)
    }
}

/// Swipe a row left to reveal its actions — the standard gesture, rebuilt
/// for rows that live outside a List (every list in this app is a hand-laid
/// VStack so the cards can carry their own shadows).
struct SwipeRow<Content: View>: View {
    @Binding var isOpen: Bool
    let actions: [SwipeAction]
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0

    private var revealWidth: CGFloat {
        guard !actions.isEmpty else { return 0 }
        return CGFloat(actions.count) * 44 + CGFloat(actions.count) * 10 + 12
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if !actions.isEmpty, isOpen || dragOffset < 0 {
                HStack(spacing: 10) {
                    ForEach(actions) { action in
                        Button {
                            Haptic.tap()
                            action.perform()
                        } label: {
                            Circle()
                                .fill(action.destructive ? Color.tomato : Color.fill)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: action.symbol)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(action.destructive ? Color.onTomato : Color.ink)
                                }
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(action.label)
                    }
                }
                .padding(.trailing, 10)
            }

            content()
                .offset(x: (isOpen ? -revealWidth : 0) + dragOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            // Horizontal-dominant only, so the page still scrolls.
                            guard !actions.isEmpty else { return }
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let base: CGFloat = isOpen ? -revealWidth : 0
                            dragOffset = min(max(value.translation.width, -revealWidth - base), -base)
                        }
                        .onEnded { value in
                            guard !actions.isEmpty else { return }
                            let projected = (isOpen ? -revealWidth : 0) + value.translation.width
                            let opening = projected < -revealWidth / 2
                            // The detent announces itself in the hand.
                            if opening != isOpen { Haptic.select() }
                            withAnimation(.plSnap) {
                                isOpen = opening
                                dragOffset = 0
                            }
                        }
                )
        }
        .animation(.plSnap, value: isOpen)
    }
}
