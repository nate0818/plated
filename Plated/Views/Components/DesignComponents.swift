import SwiftUI

/// Shared native treatments from the approved app design. Photos keep their
/// geometry even when a recipe has no image, so adding one never moves a control.
struct RecipeArtwork: View {
    var data: Data?
    var title: String
    var ratio: CGFloat = 1.45
    var radius: CGFloat = Radius.chip
    var maxHeight: CGFloat? = nil
    var height: CGFloat? = nil
    var placeholderSymbol = "fork.knife"
    var placeholderSize: CGFloat = 30
    var body: some View {
        Group {
            if let height { Color.fill.frame(height: height) }
            else { Color.fill.aspectRatio(ratio, contentMode: .fit) }
        }
            .frame(maxHeight: maxHeight)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geometry in
                    if let data, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: placeholderSymbol).font(.system(size: placeholderSize, weight: .light))
                        }
                        .foregroundStyle(Color.inkSecondary)
                        .padding(18)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            }
            .clipShape(Radius.shape(radius))
            // Cropping only clips pixels. Bound hit testing too, or a tall
            // source image can intercept a date target above its meal card.
            .contentShape(Radius.shape(radius))
            .accessibilityHidden(true)
    }
}

struct PlatedMasthead<Tools: View>: View {
    var title: String
    var wordmarkSize: CGFloat = 25
    var titleBelowTools = false
    var compact = false
    var showsCreate = true
    @ViewBuilder var tools: Tools
    @Environment(\.dynamicTypeSize) private var typeSize

    private var accessibleTitle: String {
        switch title {
        case "At home, tonight.", "The dinner plan", "The month ahead": "Plan"
        case "The recipe book": "Recipes"
        default: title
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                Text(accessibleTitle).plType(.pageTitle, .regular)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if showsCreate { EditorialAddButton() }
                tools.plChrome()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(accessibleTitle).plType(.heading)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }
                HStack { if showsCreate { EditorialAddButton() }; Spacer(minLength: 8); tools.plChrome() }
            }
        }
        .padding(.top, 6)

    }
}

struct EditorialAddButton: View {
    @Environment(\.activeAppTab) private var activeTab

    var body: some View {
        Button {
            Haptic.tap()
            NotificationCenter.default.post(name: .platedCreateRequested, object: nil)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.accentText)
                .plTapTarget()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(activeTab == .table ? "New post" : activeTab == .cookbook ? "Add a recipe" : "Add")
        .accessibilityHint(activeTab == .table ? "Share a post with your Table" : activeTab == .cookbook ? "Import, scan or write a recipe" : "Add a recipe or Table post")
        .accessibilityIdentifier("tray-create")
    }
}

struct DesignChip: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    var title: String
    var symbol: String? = nil
    var selected = false
    var action: () -> Void
    var body: some View {
        Button { Haptic.select(); action() } label: {
            HStack(spacing: 6) {
                if selected && differentiateWithoutColor {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .medium)).accessibilityHidden(true)
                }
                Text(title)
                    .plType(.footnote, selected ? .semibold : .regular)
                    .plActionLabel()
            }
            .foregroundStyle(selected ? Color.onSelection : Color.inkSecondary)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(selected ? Color.selectionFill : Color.fill, in: Radius.shape(Radius.chip))
            .contentShape(Radius.shape(Radius.chip))
        }.buttonStyle(.pressable)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct DesignIconButton: View {
    var symbol: String
    var label: String
    var accent = false
    var quiet = false
    var targetSize: CGFloat = 44
    var action: () -> Void
    var body: some View {
        Button { Haptic.tap(); action() } label: {
            Image(systemName: symbol).font(.system(size: quiet ? 22 : 18, weight: quiet ? .regular : .medium))
                .foregroundStyle(accent ? Color.onSelection : Color.ink)
                .frame(width: targetSize, height: targetSize)
                .background(accent ? Color.selectionFill : quiet ? Color.clear : Color.fill, in: Radius.shape(Radius.chip))
                .contentShape(Radius.shape(Radius.chip))
        }.buttonStyle(.pressable).accessibilityLabel(label)
    }
}

#if DEBUG
/// A local review surface: no store, account, timers or network dependencies.
private struct PlatedDesignSystemGallery: View {
    @State private var selected = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                Text("Plated design system").plType(.title, .semibold)
                VStack(alignment: .leading, spacing: Spacing.inline) {
                    Text("Editorial, made for dinner").plType(.heading, .semibold)
                    Text("Plan dinner, keep the recipe and cook together.")
                        .plType(.body).foregroundStyle(Color.inkSecondary)
                    MicroLabel("Supporting detail")
                }
                VStack(spacing: Spacing.compact) {
                    PrimaryActionButton(title: "Save recipe", systemImage: "checkmark") {}
                    PrimaryActionButton(title: "Importing recipe", busy: true) {}
                    PrimaryActionButton(title: "Save recipe") {}.disabled(true)
                    SecondaryActionButton(title: "Choose another night", systemImage: "calendar") {}
                    SecondaryActionButton(title: "Choose another night") {}.disabled(true)
                }
                VStack(alignment: .leading, spacing: Spacing.compact) {
                    DesignChip(title: "Weeknight recipes", symbol: "clock", selected: selected) {
                        selected.toggle()
                    }
                    OptionRow(icon: "book.closed", title: "Add a recipe", detail: "Paste it, scan it, or write it out") {}
                    Button("Floating control") {}
                        .plType(.callout)
                        .padding(Spacing.content)
                        .plFloatingGlass()
                }
                RecipeArtwork(data: nil, title: "Lemon butter salmon")
            }
            .foregroundStyle(Color.ink)
            .padding(Spacing.page)
            .frame(maxWidth: Layout.readableMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color.canvas)
        .onAppear { BrandFonts.registerAll() }
    }
}

#Preview("Design system / Light") {
    PlatedDesignSystemGallery().preferredColorScheme(.light)
}

#Preview("Design system / Dark") {
    PlatedDesignSystemGallery().preferredColorScheme(.dark)
}

#Preview("Design system / AX5") {
    PlatedDesignSystemGallery().environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Design system / System accessibility settings") {
    // Accessibility environment values are read-only in this SDK.
    // Configure reduced effects and contrast in the preview host's settings.
    PlatedDesignSystemGallery()
}
#endif
