import SwiftUI

/// Awards turn the useful things people already do in Plated into a kitchen
/// story. Progress is calm and permanent: no daily streaks, expiry, or loss.
struct AwardsGalleryView: View {
    let personName: String
    let awards: [PlatedAward]
    var showsProgress = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var filter: AwardFilter = .all
    @State private var selected: PlatedAward?

    private var standing: KitchenStanding { Awards.standing(for: awards) }
    private var earned: [PlatedAward] { awards.filter(\.isEarned) }
    private var visibleAwards: [PlatedAward] {
        guard showsProgress else { return earned }
        switch filter {
        case .all: return awards
        case .earned: return earned
        case .inProgress:
            return awards.filter { !$0.isEarned }.sorted { $0.progress > $1.progress }
        }
    }
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: typeSize >= .xxLarge ? 1 : 2
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 7) {
                    MicroLabel("Kitchen story")
                    Text(showsProgress ? "Small wins, worth keeping." : "\(personName)'s kitchen story.")
                        .plType(.title, .semibold)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Awards celebrate planning, cooking and bringing people together. They never expire.")
                        .plType(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                standingCard

                if showsProgress { filterBar }

                if visibleAwards.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(visibleAwards) { award in
                            awardCard(award)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 34)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
        .sheet(item: $selected) { award in
            AwardDetailSheet(award: award, showsProgress: showsProgress)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.canvas)
                .presentationCornerRadius(Radius.sheet)
                .plTapOutsideToDismiss()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Awards")
                .plType(.heading, .semibold)
                .foregroundStyle(Color.ink)
            Spacer()
            Button("Done") { dismiss() }
                .plType(.footnote, .bold)
                .plActionLabel()
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.hairline))
                .contentShape(Capsule())
                .buttonStyle(.pressable)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }

    private var standingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().fill(Color.tomato.opacity(0.12))
                    Image(systemName: standing.nextTitle == nil ? "trophy.fill" : "sparkles")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Color.tomato)
                        .plChrome()
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    MicroLabel("Kitchen level")
                    Text(standing.title)
                        .plName()
                        .plType(.title, .semibold)
                        .foregroundStyle(Color.ink)
                    Text("\(earned.count) of \(awards.count) awards · \(standing.score) points")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer(minLength: 0)
            }

            if let next = standing.nextTitle, let nextScore = standing.nextScore, showsProgress {
                VStack(spacing: 8) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.ink.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: [.tomato, .amber], startPoint: .leading, endPoint: .trailing))
                                .frame(width: proxy.size.width * standing.progress)
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text("Next: \(next)")
                        Spacer()
                        Text("\(max(0, nextScore - standing.score)) points to go")
                    }
                    .plType(.micro, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.tomatoTint, Color.mangoTint.opacity(0.72), Color.raisedFill],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Radius.shape(Radius.hero)
        )
        .overlay(Radius.shape(Radius.hero).strokeBorder(Color.tomato.opacity(0.14)))
        .shadow(color: Color.shadowWarm.opacity(0.09), radius: 20, y: 9)
    }

    private var filterBar: some View {
        HStack(spacing: 4) {
            ForEach(AwardFilter.allCases) { option in
                Button {
                    Haptic.select()
                    withAnimation(.plSnap) { filter = option }
                } label: {
                    Text(option.label)
                        .plType(.footnote, filter == option ? .bold : .medium)
                        .plActionLabel(0.72)
                        .foregroundStyle(filter == option ? Color.ink : Color.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(filter == option ? Color.raisedFill : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(filter == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.fill, in: Capsule())
    }

    private func awardCard(_ award: PlatedAward) -> some View {
        Button {
            Haptic.select()
            selected = award
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    AwardMedallion(award: award, size: 66)
                    Spacer()
                    Text(award.tier.rawValue)
                        .plType(.micro, .bold)
                        .foregroundStyle(award.isEarned ? award.tone.foreground : Color.inkSecondary)
                        .padding(.horizontal, 9)
                        .frame(minHeight: 28)
                        .background(award.isEarned ? award.tone.tint : Color.fill, in: Capsule())
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(award.title)
                        .plName()
                        .plType(.heading, .semibold)
                        .foregroundStyle(Color.ink)
                    Text(award.story)
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showsProgress {
                    AwardProgressLine(award: award)
                } else if let earnedAt = award.earnedAt {
                    Text("Earned \(earnedAt.formatted(.dateTime.month(.abbreviated).year()))")
                        .plType(.micro, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .background(Color.raisedFill, in: Radius.shape(Radius.card))
            .overlay(Radius.shape(Radius.card).strokeBorder(award.isEarned ? award.tone.foreground.opacity(0.16) : Color.hairline))
            .contentShape(Radius.shape(Radius.card))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(award.title), \(award.progressLine)")
        .accessibilityHint("Shows award details.")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.amber)
                .plChrome()
            Text(showsProgress ? "Your first award is taking shape." : "New kitchen stories are taking shape.")
                .plType(.heading, .semibold)
                .foregroundStyle(Color.ink)
            if showsProgress {
                Text("Plan a night, finish a dish or share something at the Table.")
                    .plType(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.fill, in: Radius.shape(Radius.card))
    }
}

struct AwardsPreviewCard: View {
    let awards: [PlatedAward]
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var standing: KitchenStanding { Awards.standing(for: awards) }
    private var featured: [PlatedAward] {
        let earned = awards.filter(\.isEarned).sorted { ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast) }
        let count = typeSize >= .accessibility1 ? 2 : 3
        return Array(earned.prefix(count))
    }

    var body: some View {
        Button {
            Haptic.select()
            action()
        }         label: {
            VStack(alignment: .leading, spacing: 16) {
                if featured.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No awards yet")
                            .plType(.heading, .semibold)
                            .foregroundStyle(Color.ink)
                        Text("Cook, plan, and share. Awards show up here.")
                            .plType(.caption)
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(standing.title)
                                .plName()
                                .plType(.title, .semibold)
                                .foregroundStyle(Color.ink)
                            Text("\(standing.score) points · \(awards.filter(\.isEarned).count) earned")
                                .plType(.caption)
                                .foregroundStyle(Color.inkSecondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        ForEach(featured) { award in
                            VStack(spacing: 6) {
                                AwardMedallion(award: award, size: 54)
                                Text(award.title)
                                    .plType(.micro, .semibold)
                                    .foregroundStyle(Color.inkSecondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.raisedFill, in: Radius.shape(Radius.card))
            .overlay(Radius.shape(Radius.card).strokeBorder(Color.hairline))
            .contentShape(Radius.shape(Radius.card))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(
            featured.isEmpty
                ? "No awards yet. Cook, plan, and share. Awards show up here."
                : "Awards. \(standing.title), \(standing.score) points"
        )
        .accessibilityHint("Shows every earned award and progress toward the next ones.")
    }
}

struct AwardsHighlightShelf: View {
    let awards: [PlatedAward]
    let showsProgress: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var visible: [PlatedAward] {
        let earned = awards.filter(\.isEarned)
        if showsProgress, earned.isEmpty {
            return Array(awards.sorted { $0.progress > $1.progress }.prefix(typeSize >= .accessibility1 ? 2 : 4))
        }
        return Array(earned.prefix(typeSize >= .accessibility1 ? 2 : 4))
    }

    var body: some View {
        Button {
            Haptic.select()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    MicroLabel("Awards")
                    Spacer()
                    Text("See all")
                        .plType(.caption, .bold)
                        .foregroundStyle(Color.accentText)
                }
                if visible.isEmpty {
                    Text("New kitchen stories are taking shape.")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                } else {
                    HStack(spacing: 14) {
                        ForEach(visible) { award in
                            VStack(spacing: 6) {
                                AwardMedallion(award: award, size: 50)
                                Text(award.title)
                                    .plType(.micro, .semibold)
                                    .foregroundStyle(Color.inkSecondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Awards")
        .accessibilityHint("Shows \(showsProgress ? "award progress" : "earned awards").")
    }
}

struct AwardMedallion: View {
    let award: PlatedAward
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ink.opacity(0.07), lineWidth: max(3, size * 0.07))
            Circle()
                .trim(from: 0, to: award.progress)
                .stroke(
                    award.tone.foreground,
                    style: StrokeStyle(lineWidth: max(3, size * 0.07), lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(
                    award.isEarned
                        ? LinearGradient(colors: [award.tone.tint, Color.raisedFill], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.fill, Color.raisedFill], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .padding(max(5, size * 0.10))
            Image(systemName: award.symbol)
                .font(.system(size: size * 0.31, weight: .semibold))
                .foregroundStyle(award.isEarned ? award.tone.foreground : Color.inkFaint)
                .symbolEffect(.bounce, options: .nonRepeating, value: award.isEarned)
                .plChrome()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct AwardProgressLine: View {
    let award: PlatedAward

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ink.opacity(0.07))
                    Capsule()
                        .fill(award.isEarned ? award.tone.foreground : Color.inkSecondary.opacity(0.55))
                        .frame(width: proxy.size.width * award.progress)
                }
            }
            .frame(height: 6)
            HStack {
                Text(award.progressLine)
                Spacer()
                Text("+\(award.points) pts")
            }
            .plType(.micro, .semibold)
            .foregroundStyle(Color.inkSecondary)
        }
    }
}

private struct AwardDetailSheet: View {
    let award: PlatedAward
    let showsProgress: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    DesignIconButton(symbol: "xmark", label: "Close award") { dismiss() }
                }
                AwardMedallion(award: award, size: 116)
                VStack(spacing: 7) {
                    MicroLabel("\(award.tier.rawValue) award")
                    Text(award.title)
                        .plName()
                        .plType(.display, .semibold)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                    Text(award.story)
                        .plType(.body)
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if award.isEarned, let earnedAt = award.earnedAt {
                    Label(
                        "Earned \(earnedAt.formatted(.dateTime.month(.wide).day().year()))",
                        systemImage: "checkmark.seal.fill"
                    )
                    .plType(.footnote, .bold)
                    .foregroundStyle(award.tone.foreground)
                    .padding(.horizontal, 15)
                    .frame(minHeight: 42)
                    .background(award.tone.tint, in: Capsule())
                } else if showsProgress {
                    VStack(spacing: 12) {
                        AwardProgressLine(award: award)
                        Text(award.howToEarn)
                            .plType(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .background(Color.fill, in: Radius.shape(Radius.card))
                }

                Text("Worth \(award.points) kitchen points")
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(Color.canvas)
    }
}

private enum AwardFilter: String, CaseIterable, Identifiable {
    case all, earned, inProgress
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .earned: return "Earned"
        case .inProgress: return "In progress"
        }
    }
}

private extension AwardTone {
    var foreground: Color {
        switch self {
        case .tomato: return .tomato
        case .amber: return .amber
        case .basil: return .completion
        case .grape: return .grape
        case .copper: return .copper
        case .cocoa: return .ink
        }
    }

    var tint: Color {
        switch self {
        case .tomato: return .tomatoTint
        case .amber: return .mangoTint
        case .basil: return .basilTint
        case .grape: return .grapeTint
        case .copper: return .tomatoTint
        case .cocoa: return .fill
        }
    }
}
