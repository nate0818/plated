import SwiftUI
import SwiftData

/// One thing this household can earn. Countable ones carry their progress
/// so a locked badge still tells you how close you are — a dashed circle
/// that never moves teaches nothing.
struct Badge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let earned: Bool
    /// nil for one-shot badges; 0…1 for the ones you climb toward.
    let progress: Double?
    let progressLabel: String?

    init(id: String, title: String, detail: String, symbol: String,
         have: Int, need: Int) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.earned = have >= need
        self.progress = need > 1 ? min(Double(have) / Double(need), 1) : nil
        self.progressLabel = need > 1 && have < need ? "\(have) of \(need)" : nil
    }
}

/// The deeper shelf: every number this household has run up, and the
/// badges it has earned or is walking toward. Lives one tap under Home's
/// stat tiles so the main page can stay about the people.
struct HouseholdStatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var recipes: [Recipe]
    @Query(filter: #Predicate<TablePost> { !$0.isDiscover }) private var posts: [TablePost]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var meals: [PlannedMeal]

    private var dishPosts: [TablePost] { posts.filter { $0.kind == "dish" } }
    private var kissCount: Int { posts.filter(\.hasChefsKiss).count }
    private var platesEarned: Int { posts.reduce(0) { $0 + $1.totalPlates } }
    private var nightsPlated: Int { meals.count }

    /// The most nights ever planned inside one calendar week — the badge
    /// says "a week, plated", so counting every dinner ever would be a
    /// different claim entirely.
    private var bestWeek: Int {
        let calendar = Calendar.current
        let weeks = Dictionary(grouping: meals) { meal in
            calendar.dateInterval(of: .weekOfYear, for: meal.date)?.start ?? meal.date
        }
        return weeks.values.map(\.count).max() ?? 0
    }

    private var badges: [Badge] {
        [
            Badge(id: "first-recipe", title: "First recipe",
                  detail: "Write a dish into the cookbook.",
                  symbol: "book.closed", have: recipes.count, need: 1),
            Badge(id: "ten-recipes", title: "Ten dishes deep",
                  detail: "A cookbook worth cooking from.",
                  symbol: "books.vertical", have: recipes.count, need: 10),
            Badge(id: "first-post", title: "First plate shared",
                  detail: "Post something you cooked to the Table.",
                  symbol: "circle.circle", have: dishPosts.count, need: 1),
            Badge(id: "first-kiss", title: "First chef's kiss",
                  detail: "Earn the table's highest compliment.",
                  symbol: "sparkles", have: kissCount, need: 1),
            Badge(id: "ten-plates", title: "Ten plates earned",
                  detail: "Ten reactions across everything you've shared.",
                  symbol: "hands.clap", have: platesEarned, need: 10),
            Badge(id: "first-save", title: "First save",
                  detail: "Someone cooked your dish at their table.",
                  symbol: "arrow.down.heart", have: Awards.totalSavesRecorded, need: 1),
            Badge(id: "full-table", title: "Full table",
                  detail: "Three seats filled at your household.",
                  symbol: "person.3", have: members.count, need: 3),
            Badge(id: "week-planned", title: "A week, plated",
                  detail: "Seven nights planned inside one week.",
                  symbol: "calendar", have: bestWeek, need: 7)
        ]
    }

    private var earnedCount: Int { badges.filter(\.earned).count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                numbers
                badgeShelf
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, Layout.floatingChromeInset)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                Haptic.tap()
                dismiss()
            } label: {
                Circle()
                    .strokeBorder(Color.hairline, lineWidth: 1.5)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 1) {
                MicroLabel("\(earnedCount) of \(badges.count) earned")
                Text("All stats")
                    .font(.gabarito(20, .semibold))
                    .foregroundStyle(Color.ink)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(Color.canvas)
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel("The count")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize >= .accessibility1 ? 2 : 3),
                spacing: 10
            ) {
                statTile("Kisses", kissCount, "sparkles", accent: kissCount > 0)
                statTile("Plates", platesEarned, "hands.clap")
                statTile("Recipes", recipes.count, "book.closed")
                statTile("Posts", dishPosts.count, "circle.circle")
                statTile("Saves", Awards.totalSavesRecorded, "arrow.down.heart")
                statTile("Nights", nightsPlated, "calendar")
            }
        }
    }

    private func statTile(_ label: String, _ value: Int, _ symbol: String, accent: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent ? Color.mango : Color.inkFaint)
            Text("\(value)")
                .font(.gabarito(21, .semibold))
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText())
                .animation(.plSnap, value: value)
            Text(label.uppercased())
                .font(.jakarta(9, .extraBold))
                .tracking(0.5)
                .foregroundStyle(Color.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .frame(minHeight: 82)
        .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
        .accessibilityElement(children: .combine)
    }

    private var badgeShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel("Badges")
            VStack(spacing: 8) {
                ForEach(badges) { badge in
                    badgeRow(badge)
                }
            }
        }
        .animation(.plPop, value: earnedCount)
        .sensoryFeedback(.success, trigger: earnedCount) { old, new in new > old }
    }

    private func badgeRow(_ badge: Badge) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(badge.earned ? Color.basilTint : Color.clear)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if !badge.earned {
                            Circle().strokeBorder(
                                Color.hairlineDashed,
                                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                            )
                        }
                    }
                Image(systemName: badge.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(badge.earned ? Color.basil : Color.inkFaint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(badge.title)
                    .font(.jakarta(14, .bold))
                    .foregroundStyle(badge.earned ? Color.ink : Color.inkSecondary)
                Text(badge.progressLabel ?? badge.detail)
                    .font(.jakarta(12, .medium))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(2)

                if let progress = badge.progress, !badge.earned {
                    // A quiet climb: hairline track, basil fill, no drama.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.hairlineSoft)
                            Capsule()
                                .fill(Color.basil)
                                .frame(width: max(3, geo.size.width * progress))
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 3)
                    .animation(.plSnap, value: progress)
                }
            }

            Spacer(minLength: 4)

            if badge.earned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.basil)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.canvas)
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
        // Earned is a green tick and a green circle — state that a
        // screen reader can't see unless it's said out loud.
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            badge.earned ? "Earned" : (badge.progressLabel.map { "Not earned yet, \($0)" } ?? "Not earned yet")
        )
    }
}
