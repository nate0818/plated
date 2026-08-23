import SwiftUI

/// One thing a swipe can reveal. The destructive one wears ink, not
/// tomato: tomato is earned colour and belongs to good news, so the
/// weight here comes from fill rather than hue.
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

    /// Taking a line off a screen, not out of the household. Deliberately
    /// not destructive: an activity entry clears, but the plate, the comment
    /// and the save it describes all still happened, and giving that the
    /// same weight as removing a person overstates it.
    static func clear(_ perform: @escaping () -> Void) -> SwipeAction {
        SwipeAction(symbol: "xmark", label: "Clear", perform: perform)
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
    /// Where the drag currently being tracked began — the only reliable way
    /// to tell a fresh gesture from a continuing one, since a cancelled
    /// gesture never announces itself.
    @State private var gestureStart: CGPoint?

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
                            // Destructive reads as weight, not as tomato.
                            // Tomato is earned colour — the + button, a plate
                            // landing, a committing CTA — and spending it on
                            // "remove" puts the loudest thing on the screen
                            // next to the thing you least want mis-tapped.
                            Circle()
                                .fill(action.destructive ? Color.ink : Color.fill)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: action.symbol)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(action.destructive ? Color.canvas : Color.ink)
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
                // BEFORE the offset, and that ordering is the whole point.
                // `.offset` is a geometry effect: it moves the rendering of
                // what it wraps and does not move anything composed on top
                // afterwards. Attached after, this catcher stayed at the
                // row's unshifted full-width frame and sat directly over the
                // strip the buttons had just been revealed in — so every tap
                // on Message or Remove hit `Color.clear` and merely closed
                // the row. Attached here it travels with the content, and
                // the revealed strip stays the buttons'.
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
                .offset(x: (isOpen ? -revealWidth : 0) + dragOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            // Horizontal-dominant only, so the page still
                            // scrolls. Once proven, the drag keeps the
                            // row even if the finger curves upward.
                            guard !actions.isEmpty else { return }
                            // Re-arm on a NEW gesture, keyed by where it
                            // started. A cancelled drag — app backgrounded
                            // mid-swipe, a system edge gesture, WeekView's
                            // `.draggable` lift stealing the touch — never
                            // reaches `onEnded`, so a latch reset only there
                            // can strand true and let the next vertical
                            // flick through.
                            if gestureStart != value.startLocation {
                                gestureStart = value.startLocation
                                isHorizontal = false
                            }
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
