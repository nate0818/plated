import SwiftUI

/// One selection treatment for planner, grocery and audience controls.
struct EditorialSegments<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var stacked = false
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            ForEach(options, id: \.self) { option in
                Button {
                    guard selection != option else { return }
                    Haptic.select()
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) { selection = option }
                } label: {
                    Text(label(option))
                        .plType(.footnote, selection == option ? .semibold : .medium)
                        .plActionLabel()
                        .foregroundStyle(selection == option ? Color.onSelection : Color.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: stacked ? 48 : 44)
                        .background {
                            if selection == option {
                                shape.fill(Color.selectionFill)
                                    .matchedGeometryEffect(id: "selection", in: indicator)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.hairlineSoft, in: shape)
    }

    private var shape: RoundedRectangle {
        Radius.shape(stacked ? Radius.row : 100)
    }
}
