import SwiftUI

/// Shared native treatments from the approved app design. Photos keep their
/// geometry even when a recipe has no image, so adding one never moves a control.
struct RecipeArtwork: View {
    var data: Data?
    var title: String
    var ratio: CGFloat = 1.45
    var radius: CGFloat = Radius.hero
    var body: some View {
        Color.fill
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    if let data, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "fork.knife").font(.system(size: 30, weight: .light))
                            Text(title).plType(.footnote, .medium).multilineTextAlignment(.center).lineLimit(3)
                        }
                        .foregroundStyle(Color.inkSecondary)
                        .padding(18)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            }
            .clipShape(Radius.shape(radius))
            .accessibilityHidden(true)
    }
}

struct PlatedMasthead<Tools: View>: View {
    var title: String
    /// Three header actions need their own row so the title keeps its width.
    var titleBelowTools = false
    @ViewBuilder var tools: Tools
    var body: some View {
        Group {
            if titleBelowTools {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 12) {
                        PlatedWordmark(size: 23)
                        Spacer(minLength: 8)
                        tools.plChrome()
                    }
                    Text(title).plType(.hero, .semibold).foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 9) {
                        PlatedWordmark(size: 23)
                        Text(title).plType(.hero, .semibold).foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    tools.padding(.top, 2).plChrome()
                }
            }
        }
        .padding(.top, 12).padding(.bottom, 6)
    }
}

struct DesignChip: View {
    var title: String
    var symbol: String? = nil
    var selected = false
    var action: () -> Void
    var body: some View {
        Button { Haptic.select(); action() } label: {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .medium)) }
                Text(title).plType(.footnote, selected ? .semibold : .regular)
            }
            .foregroundStyle(selected ? Color.onTomato : Color.inkSecondary)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(selected ? Color.tomato : Color.fill, in: Capsule())
            .contentShape(Capsule())
        }.buttonStyle(.pressable)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct DesignIconButton: View {
    var symbol: String
    var label: String
    var accent = false
    var action: () -> Void
    var body: some View {
        Button { Haptic.tap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                .foregroundStyle(accent ? Color.onTomato : Color.ink)
                .frame(width: 44, height: 44)
                .background(accent ? Color.tomato : Color.fill, in: Circle())
                .contentShape(Circle())
        }.buttonStyle(.pressable).accessibilityLabel(label)
    }
}
