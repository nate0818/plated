import SwiftUI
import SwiftData

/// The mark on a badge or a count. Most are SF Symbols, but a plate is a
/// plate — the app draws its own, and reaching for `hands.clap` to stand
/// in for one was the loudest wrong note on this page.
enum BadgeMark {
    case symbol(String)
    case plate
}

struct BadgeMarkView: View {
    let mark: BadgeMark
    var size: CGFloat
    var color: Color = .inkFaint

    var body: some View {
        Group {
            switch mark {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(color)
            case .plate:
                PlateReactionGlyph(filled: false, size: size * 1.5, tone: color)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One thing this household can earn. Countable ones carry their progress
/// so a locked badge tells you how close you are — Starbucks' locked
/// rewards never say "locked", they say "61★ away", and the distance is
/// the part that makes someone act.
struct Badge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let mark: BadgeMark
    let have: Int
    let need: Int

    var earned: Bool { have >= need }
    /// 0…1 always, so the ring and the "what's next" pick both have a
    /// number to sort on — including the one-shot badges.
    var fraction: Double { min(Double(have) / Double(max(need, 1)), 1) }
    /// Only the ones you climb toward get a count under the medal.
    var progressLabel: String? {
        guard need > 1, !earned else { return nil }
        return "\(have) of \(need)"
    }
    var remainingLine: String {
        let left = max(need - have, 0)
        return left == 1 ? "One to go" : "\(left) to go"
    }
}

/// The deeper shelf: every number this household has run up, and the
/// badges it has earned or is walking toward. Lives one tap under Home's
/// count so the main page can stay about the people.
struct HouseholdStatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var recipes: [Recipe]
    @Query(filter: #Predicate<TablePost> { !$0.isDiscover }) private var posts: [TablePost]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var meals: [PlannedMeal]

    @State private var opened: Badge?

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
            Badge(id: "first-dinner", title: "First dinner",
                  detail: "Put a night on the plan.",
                  mark: .symbol("fork.knife"), have: nightsPlated, need: 1),
            Badge(id: "first-recipe", title: "First recipe",
                  detail: "Write a dish into the cookbook.",
                  mark: .symbol("text.book.closed"), have: recipes.count, need: 1),
            Badge(id: "first-post", title: "First plate shared",
                  detail: "Bring something you cooked to the table.",
                  mark: .symbol("table.furniture"), have: dishPosts.count, need: 1),
            Badge(id: "first-kiss", title: "First chef's kiss",
                  detail: "Ten plates on one dish — the table's highest compliment.",
                  mark: .symbol("sparkles"), have: kissCount, need: 1),
            Badge(id: "first-save", title: "Cooked elsewhere",
                  detail: "Someone cooked your dish at their own table.",
                  mark: .symbol("bookmark"), have: Awards.totalSavesRecorded, need: 1),
            Badge(id: "full-table", title: "Full table",
                  detail: "Three seats filled at your household.",
                  mark: .symbol("person.3"), have: members.count, need: 3),
            Badge(id: "ten-recipes", title: "Ten dishes deep",
                  detail: "A cookbook worth cooking from.",
                  mark: .symbol("books.vertical"), have: recipes.count, need: 10),
            Badge(id: "ten-plates", title: "Ten happy plates",
                  detail: "Ten plates across everything you've shared.",
                  mark: .plate, have: platesEarned, need: 10),
            Badge(id: "week-planned", title: "A week, plated",
                  detail: "Seven nights planned inside one week.",
                  mark: .symbol("calendar"), have: bestWeek, need: 7)
        ]
    }

    private var earnedCount: Int { badges.filter(\.earned).count }

    /// The badge this household will get next: furthest along, and among
    /// ties the one that asks for least. Putting the closest goal at the
    /// top is the whole of the Starbucks progress effect — a number you
    /// can see yourself closing is a number you act on.
    private var nextUp: Badge? {
        badges
            .filter { !$0.earned }
            .sorted { ($0.fraction, Double(-$0.need)) > ($1.fraction, Double(-$1.need)) }
            .first
    }

    private var columns: Int { typeSize >= .accessibility1 ? 2 : 3 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                numbers
                if let nextUp { nextUpCard(nextUp) }
                badgeShelf
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, Layout.floatingChromeInset)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
        .sheet(item: $opened) { badge in
            BadgeDetailSheet(badge: badge)
        }
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

    // MARK: The count
    // Same shape as Home's, one row deeper. These six get a mark each
    // because six numbers on one screen do need telling apart — but the
    // mark is the thing itself (the app's own plate, a real table), sized
    // down and faint, the way X hangs a glyph off a number.

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 14) {
            MicroLabel("The count")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns),
                spacing: 22
            ) {
                countCell("Dinners", nightsPlated, .symbol("fork.knife"))
                countCell("Happy plates", platesEarned, .plate)
                countCell("Chef's kisses", kissCount, .symbol("sparkles"), accent: kissCount > 0)
                countCell("Recipes", recipes.count, .symbol("text.book.closed"))
                countCell("On the table", dishPosts.count, .symbol("table.furniture"))
                countCell("Saved by others", Awards.totalSavesRecorded, .symbol("bookmark"))
            }
        }
    }

    private func countCell(_ label: String, _ value: Int, _ mark: BadgeMark, accent: Bool = false) -> some View {
        VStack(spacing: 5) {
            BadgeMarkView(mark: mark, size: 13, color: accent ? .mango : .inkFaint)
            CountBlock(value: "\(value)", label: label, accent: accent)
        }
    }

    // MARK: What's next

    private func nextUpCard(_ badge: Badge) -> some View {
        Button {
            Haptic.tap()
            opened = badge
        } label: {
            HStack(spacing: 14) {
                BadgeMedal(badge: badge, size: 54)
                VStack(alignment: .leading, spacing: 3) {
                    MicroLabel("Closest badge")
                    Text(badge.title)
                        .font(.jakarta(15, .bold))
                        .foregroundStyle(Color.ink)
                    Text(badge.progressLabel.map { "\($0) · \(badge.remainingLine)" } ?? badge.detail)
                        .font(.jakarta(12, .medium))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(16)
            .background(Color.canvas)
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
    }

    // MARK: The shelf
    // A grid, not a stack of full-width rows. Untappd and Apple's Awards
    // both browse as medals for the same reason: the gaps are the point.
    // Nine cards down the page hid that behind a lot of prose, and the
    // prose belongs in the tap, not the shelf.

    private var badgeShelf: some View {
        VStack(alignment: .leading, spacing: 16) {
            MicroLabel("Badges")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
                spacing: 24
            ) {
                ForEach(badges) { badge in
                    badgeCell(badge)
                }
            }
        }
        .animation(.plPop, value: earnedCount)
        .sensoryFeedback(.success, trigger: earnedCount) { old, new in new > old }
    }

    private func badgeCell(_ badge: Badge) -> some View {
        Button {
            Haptic.tap()
            opened = badge
        } label: {
            VStack(spacing: 8) {
                BadgeMedal(badge: badge)
                Text(badge.title)
                    .font(.jakarta(11.5, .bold))
                    .foregroundStyle(badge.earned ? Color.ink : Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                // Earned states carry no chip at all — the full ring says
                // it, and absence of a nag is the reward.
                if let label = badge.progressLabel {
                    Text(label)
                        .font(.jakarta(10, .semibold))
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            badge.earned ? "Earned" : (badge.progressLabel.map { "Not earned yet, \($0)" } ?? "Not earned yet")
        )
    }
}

/// One badge as a medal. A single ring carries every state: it fills as
/// the household climbs and a closed ring means earned, so the shelf
/// never has to draw a lock or a tick to say where things stand.
struct BadgeMedal: View {
    let badge: Badge
    var size: CGFloat = 68

    var body: some View {
        ZStack {
            Circle()
                .fill(badge.earned ? Color.basilTint : Color.clear)
            // Both rings are strokes on the same inset circle, so the
            // filled arc lands exactly on the track it is filling.
            Circle()
                .stroke(Color.hairline, lineWidth: 2.5)
                .padding(1.25)
            Circle()
                .trim(from: 0, to: badge.fraction)
                .stroke(Color.basil, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .padding(1.25)
                .rotationEffect(.degrees(-90))
            BadgeMarkView(
                mark: badge.mark,
                size: size * 0.26,
                color: badge.earned ? .basil : .inkFaint
            )
        }
        .frame(width: size, height: size)
        .animation(.plSettle, value: badge.fraction)
    }
}

/// The prose the shelf doesn't have room for: what this badge is, and
/// exactly how far off it is.
struct BadgeDetailSheet: View {
    let badge: Badge
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            BadgeMedal(badge: badge, size: 104)
                .padding(.top, 30)

            Text(badge.title)
                .font(.gabarito(22, .semibold))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)

            Text(badge.detail)
                .font(.jakarta(14, .medium))
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 28)

            if badge.earned {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Earned")
                        .font(.jakarta(13, .bold))
                }
                .foregroundStyle(Color.basil)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Color.basilTint, in: Capsule())
            } else if let label = badge.progressLabel {
                Text("\(label) · \(badge.remainingLine)")
                    .font(.jakarta(13, .bold))
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .overlay(Capsule().strokeBorder(Color.hairline))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }
}
