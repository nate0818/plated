import SwiftUI

/// One thing a swipe can reveal. Tomato is reserved for the destructive
/// one — everything else stays ink, per the house rule about earned colour.
struct SwipeAction: Identifiable {
    /// Stable across body passes — a fresh UUID each time would rebuild
    /// the revealed buttons under the user's finger.
    var id: String { label }
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
    /// Latched the moment a drag proves itself horizontal. Without it,
    /// `onEnded` judged a vertical scroll flick with a little sideways
    /// drift as a swipe and popped the row open after ordinary scrolling
    /// — the row never moved during the drag, then jumped at the end.
    @State private var isHorizontal = false

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
                // The swipe is an accelerator, never the only door: the
                // same actions hang off the row for VoiceOver and for
                // anyone who can't manage the gesture.
                .accessibilityActions {
                    ForEach(actions) { action in
                        Button(action.label) { action.perform() }
                    }
                }
                .offset(x: (isOpen ? -revealWidth : 0) + dragOffset)
                .overlay {
                    // An open row closes on a tap anywhere in it, the way
                    // every list on this platform behaves. Without this the
                    // tap fell through to the row and pushed a page over
                    // the actions the user had just revealed.
                    if isOpen {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                            .accessibilityHidden(true)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            // Horizontal-dominant only, so the page still
                            // scrolls. Once proven, the drag keeps the
                            // row even if the finger curves upward.
                            guard !actions.isEmpty else { return }
                            if !isHorizontal {
                                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                isHorizontal = true
                            }
                            let base: CGFloat = isOpen ? -revealWidth : 0
                            dragOffset = min(max(value.translation.width, -revealWidth - base), -base)
                        }
                        .onEnded { value in
                            defer { isHorizontal = false }
                            guard !actions.isEmpty, isHorizontal else {
                                if dragOffset != 0 { withAnimation(.plSnap) { dragOffset = 0 } }
                                return
                            }
                            // Predicted, not raw: a short fast flick is a
                            // swipe even though the finger barely moved.
                            let projected = (isOpen ? -revealWidth : 0) + value.predictedEndTranslation.width
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

    private func close() {
        withAnimation(.plSnap) {
            isOpen = false
            dragOffset = 0
        }
    }
}
