import SwiftUI

/// Whether the perch is currently welcome on screen. A pushed page that
/// docks its own bottom CTA (RecipeDetailView's "Plate it") would
/// otherwise have a fork sitting on it.
///
/// Deliberately NOT a PreferenceKey: preferences do not reliably
/// propagate out of a NavigationStack's pushed destination, so the
/// shell never heard the request. Shared observable state does.
@Observable
final class PerchVisibility {
    /// Counted, not toggled: two pages can ask for quiet at once (a push
    /// arriving while another is leaving) and the last one to finish must
    /// not un-hide it for the one still on screen.
    private(set) var hiddenRequests = 0
    var isHidden: Bool { hiddenRequests > 0 }

    func retain() { hiddenRequests += 1 }
    func release() { hiddenRequests = max(0, hiddenRequests - 1) }
}

private struct PerchVisibilityKey: EnvironmentKey {
    static let defaultValue = PerchVisibility()
}

extension EnvironmentValues {
    var perchVisibility: PerchVisibility {
        get { self[PerchVisibilityKey.self] }
        set { self[PerchVisibilityKey.self] = newValue }
    }
}

private struct HidesProngsbyPerch: ViewModifier {
    @Environment(\.perchVisibility) private var visibility

    func body(content: Content) -> some View {
        content
            .onAppear { visibility.retain() }
            .onDisappear { visibility.release() }
    }
}

extension View {
    /// Retire the perch for as long as this view is on screen.
    func hidesProngsbyPerch() -> some View {
        modifier(HidesProngsbyPerch())
    }
}

/// Prongsby's seat, now that he's out of the tab bar: one puck riding
/// above the floating bar, drawn once in the shell and inherited by every
/// tab and every page pushed inside one.
///
/// It wears the tab bar's own recipe — canvas under material, navHairline
/// border, float shadow — so the two read as one cluster of floating
/// chrome rather than a new species. The canvas fill UNDER the material is
/// load-bearing: ProngsbyGlyph cuts its eyes and smile out of canvas, and
/// a material-only puck over a photo-heavy feed would let the backdrop
/// bleed through and murk his face.
struct ProngsbyPerch: View {
    /// `@Observable`, so reading `thinking` here is enough to track it.
    let session: ProngsbySession
    let action: () -> Void

    /// He arrives wearing his name and gives it up once you've met him.
    @AppStorage("prongsbyPerchNamed") private var showsName = true

    var body: some View {
        Button {
            Haptic.tap()
            if showsName {
                withAnimation(.plSnap) { showsName = false }
            }
            action()
        } label: {
            HStack(spacing: 7) {
                glyph
                if showsName {
                    Text("Prongsby")
                        .plType(.micro)
                        .foregroundStyle(Color.ink)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .padding(.horizontal, showsName ? 14 : 0)
            .frame(width: showsName ? nil : Layout.perchHeight, height: Layout.perchHeight)
            .background {
                Capsule()
                    .fill(Color.canvas.opacity(0.94))
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.navHairline))
            }
            .overlay(alignment: .topTrailing) {
                // Status, not news: he's still cooking an answer you can't
                // see because the sheet is closed.
                if session.thinking {
                    Circle()
                        .fill(Color.basil)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 2))
                        .offset(x: 1, y: -1)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .plFloatShadow()
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .animation(.plSnap, value: session.thinking)
        .accessibilityLabel("Ask Prongsby")
        .accessibilityHint(session.thinking ? "Prongsby is working on your answer" : "Opens your cooking companion")
    }

    @ViewBuilder
    private var glyph: some View {
        // ProngsbyIdleGlyph sits still under Reduce Motion on its own now.
        if session.thinking {
            ProngsbyIdleGlyph(size: 24, tone: .ink)
        } else {
            ProngsbyGlyph(size: 24, tone: .ink)
        }
    }
}
