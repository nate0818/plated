import SwiftUI

/// The setup flow shares the same quiet paper as the rest of Editorial.
struct OnboardingAtmosphere: View {
    var body: some View {
        Color.canvas.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// A toque, drawn rather than borrowed.
///
/// SF Symbols has a frying pan and a fork and knife and no chef's hat, and
/// the emoji is a whole person. Three puffs and a band is the whole shape,
/// and drawing it means it takes the app's own colours and sits at whatever
/// size the seat it lands on happens to be.
struct ChefHat: View {
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            // The crown: three overlapping puffs.
            Circle()
                .frame(width: size * 0.46, height: size * 0.46)
                .offset(x: -size * 0.24, y: -size * 0.10)
            Circle()
                .frame(width: size * 0.56, height: size * 0.56)
                .offset(y: -size * 0.22)
            Circle()
                .frame(width: size * 0.46, height: size * 0.46)
                .offset(x: size * 0.24, y: -size * 0.10)
            // The band.
            RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                .frame(width: size * 0.62, height: size * 0.26)
                .offset(y: size * 0.20)
        }
        .frame(width: size, height: size)
        .foregroundStyle(Color.canvas)
        .shadow(color: Color.ink.opacity(0.16), radius: 3, y: 1)
    }
}

/// The seats arriving one at a time, and the hat landing on whoever cooks.
///
/// Staggered rather than simultaneous: four circles appearing together is a
/// picture, four arriving in order is a table filling up. The hat comes last
/// and from above, because it is the answer to a question the other four
/// have just finished asking.
struct TourSeats: View {
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var seated = 0
    @State private var hatOn = false

    private let seats: [(String, PersonTone)] = [
        ("A", .tomatoPair), ("C", .basilPair), ("N", .grapePair), ("A", .amberPair),
    ]
    /// The one at the stove tonight.
    private let cooking = 2

    var body: some View {
        HStack(spacing: -12) {
            ForEach(Array(seats.enumerated()), id: \.offset) { index, seat in
                AvatarCircle(initials: seat.0, tone: seat.1, size: 62)
                    .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 3))
                    .overlay(alignment: .top) {
                        if index == cooking {
                            ChefHat(size: 30)
                                .offset(y: hatOn ? -18 : -46)
                                .opacity(hatOn ? 1 : 0)
                                .rotationEffect(.degrees(hatOn ? -12 : 4), anchor: .bottom)
                        }
                    }
                    .scaleEffect(index < seated ? 1 : 0.6)
                    .opacity(index < seated ? 1 : 0)
                    // Later seats sit above earlier ones, so the hat is
                    // never clipped by the neighbour it overlaps.
                    .zIndex(Double(index))
            }
        }
        .frame(height: 96)
        .onAppear { play() }
        .onChange(of: isActive) { _, active in
            if active { play() } else { reset() }
        }
        .accessibilityHidden(true)
    }

    private func play() {
        guard isActive else { return }
        guard !reduceMotion else {
            seated = seats.count
            hatOn = true
            return
        }
        reset()
        for index in seats.indices {
            withAnimation(.plPop.delay(Double(index) * 0.09)) { seated = index + 1 }
        }
        withAnimation(.plPop.delay(Double(seats.count) * 0.09 + 0.14)) { hatOn = true }
    }

    private func reset() {
        seated = 0
        hatOn = false
    }
}

/// A real Plan row in miniature: date, dish and cook are the three anchors
/// the full week uses. They arrive in reading order, then the planned mark
/// confirms the assignment.
struct TourPlanRow: View {
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shellVisible = false
    @State private var plateVisible = false
    @State private var cookVisible = false
    @State private var plannedVisible = false

    private var tonight: Date { Calendar.current.startOfDay(for: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("TONIGHT")
                    .plType(.micro, .bold)
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.basil)
                        .frame(width: 6, height: 6)
                        .scaleEffect(plannedVisible ? 1 : 0.2)
                    Text("PLANNED")
                        .plType(.micro, .bold)
                        .foregroundStyle(Color.inkSecondary)
                }
                .opacity(plannedVisible ? 1 : 0)
            }
            .plChrome()
            .padding(.horizontal, 4)

            HStack(spacing: 11) {
                PlanDateColumn(date: tonight)

                TourPlate(
                    asset: "TourNachos",
                    fallbackTitle: "Sheet-pan nachos",
                    diameter: 66
                )
                .scaleEffect(plateVisible ? 1 : 0.76)
                .opacity(plateVisible ? 1 : 0)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Sheet-pan nachos")
                        .plType(.body, .bold)
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        AvatarCircle(initials: "A", tone: .basilPair, size: 24)
                            .overlay(alignment: .topTrailing) {
                                ChefHat(size: 13)
                                    .offset(x: 4, y: -6)
                            }
                        Text("Alex is cooking")
                            .plType(.caption, .semibold)
                            .foregroundStyle(Color.inkSecondary)
                            .lineLimit(1)
                    }
                    .offset(x: cookVisible ? 0 : 10)
                    .opacity(cookVisible ? 1 : 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(Color.cardFill, in: Radius.shape(Radius.card))
            .overlay {
                Radius.shape(Radius.card)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            }
            .plCardShadow()
        }
        .frame(maxWidth: 330)
        .scaleEffect(shellVisible ? 1 : 0.94)
        .offset(y: shellVisible ? 0 : 18)
        .opacity(shellVisible ? 1 : 0)
        .plChrome()
        .task(id: isActive) { await play() }
        .accessibilityHidden(true)
    }

    @MainActor
    private func play() async {
        reset()
        guard isActive else { return }
        guard !reduceMotion else {
            finish()
            return
        }

        guard await pause(70) else { return }
        withAnimation(.plSettle) { shellVisible = true }
        guard await pause(170) else { return }
        withAnimation(.plPop) { plateVisible = true }
        guard await pause(180) else { return }
        withAnimation(.plSnap) { cookVisible = true }
        guard await pause(190) else { return }
        withAnimation(.plPop) { plannedVisible = true }
    }

    @MainActor
    private func reset() {
        withAnimation(nil) {
            shellVisible = false
            plateVisible = false
            cookVisible = false
            plannedVisible = false
        }
    }

    @MainActor
    private func finish() {
        withAnimation(nil) {
            shellVisible = true
            plateVisible = true
            cookVisible = true
            plannedVisible = true
        }
    }

    private func pause(_ milliseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

/// The month stays quiet in the back while a usable week lifts toward the
/// person. Nights then fill left to right and today rises into place.
struct TourWeek: View {
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var monthVisible = false
    @State private var weekVisible = false
    @State private var planned = 0
    @State private var todayUp = false
    @State private var cookAssigned = false

    private let nights = 7
    private let today = 3
    private let done = 3

    private var symbols: [String] {
        let calendar = Calendar.current
        let all = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(all[first...] + all[..<first])
    }

    private var monthName: String {
        Date.now.formatted(.dateTime.month(.wide)).uppercased()
    }

    var body: some View {
        ZStack(alignment: .top) {
            monthGrid
                .opacity(monthVisible ? 0.72 : 0)
                .scaleEffect(monthVisible ? 1 : 0.96, anchor: .top)

            weekStrip
                .offset(y: weekVisible ? 104 : 126)
                .scaleEffect(weekVisible ? 1 : 0.94)
                .opacity(weekVisible ? 1 : 0)
        }
        .frame(maxWidth: 330, minHeight: 214, alignment: .top)
        .plChrome()
        .task(id: isActive) { await play() }
        .accessibilityHidden(true)
    }

    private var monthGrid: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(monthName)
                    .plType(.micro, .bold)
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
                Text("MONTH")
                    .plType(.micro, .semibold)
                    .foregroundStyle(Color.inkSecondary)
            }
            .plChrome()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<35, id: \.self) { cell in
                    if (2...32).contains(cell) {
                        Text("\(cell - 1)")
                            .font(.sans(9, cell == 17 ? .bold : .medium))
                            .foregroundStyle(cell == 17 ? Color.ink : Color.inkSecondary)
                            .frame(maxWidth: .infinity, minHeight: 13)
                            .background(cell == 17 ? Color.fill : Color.clear, in: Circle())
                            .plChrome()
                    } else {
                        Color.clear.frame(height: 13)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: 318)
        .background(Color.cardFill.opacity(0.86), in: Radius.shape(Radius.card))
        .overlay {
            Radius.shape(Radius.card)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
    }

    private var weekStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THIS WEEK")
                .plType(.micro, .bold)
                .foregroundStyle(Color.inkSecondary)
                .plChrome()

            HStack(spacing: 5) {
                ForEach(0..<nights, id: \.self) { day in
                    let isToday = day == today
                    VStack(spacing: 3) {
                        Text(symbols[day])
                            .plType(.micro, .semibold)
                            .foregroundStyle(isToday ? Color.olive : Color.inkSecondary)
                        Text("\(day + 12)")
                            .plType(.caption, .bold)
                            .foregroundStyle(Color.ink)
                            .monospacedDigit()
                        Circle()
                            .fill(day <= done ? Color.basil : Color.hairline)
                            .frame(width: 5, height: 5)
                            .scaleEffect(day < planned ? 1 : 0)
                    }
                    .plChrome()
                    .frame(maxWidth: .infinity)
                    .frame(height: isToday ? 58 : 52)
                    .background(isToday ? Color.oliveTint : Color.fill.opacity(0.72),
                                in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .strokeBorder(isToday ? Color.olive.opacity(0.16) : Color.hairline,
                                          lineWidth: 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isToday {
                            AvatarCircle(initials: "A", tone: .basilPair, size: 18)
                                .overlay(alignment: .topTrailing) {
                                    ChefHat(size: 10)
                                        .offset(x: 3, y: -5)
                                }
                                .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 2))
                                .scaleEffect(cookAssigned ? 1 : 0.35)
                                .opacity(cookAssigned ? 1 : 0)
                                .offset(x: 5, y: -7)
                        }
                    }
                    .offset(y: isToday && todayUp ? -6 : 0)
                    .opacity(day < planned ? 1 : 0.34)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 330)
        .background(Color.cardFill, in: Radius.shape(Radius.card))
        .overlay {
            Radius.shape(Radius.card)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
        .plCardShadow()
    }

    @MainActor
    private func play() async {
        reset()
        guard isActive else { return }
        guard !reduceMotion else {
            finish()
            return
        }

        guard await pause(60) else { return }
        withAnimation(.plSettle) { monthVisible = true }
        guard await pause(170) else { return }
        withAnimation(.plSettle) { weekVisible = true }
        for day in 1...nights {
            guard await pause(65) else { return }
            withAnimation(.plSnap) { planned = day }
        }
        guard await pause(100) else { return }
        withAnimation(.plPop) { todayUp = true }
        guard await pause(150) else { return }
        withAnimation(.plPop) { cookAssigned = true }
    }

    @MainActor
    private func reset() {
        withAnimation(nil) {
            monthVisible = false
            weekVisible = false
            planned = 0
            todayUp = false
            cookAssigned = false
        }
    }

    @MainActor
    private func finish() {
        withAnimation(nil) {
            monthVisible = true
            weekVisible = true
            planned = nights
            todayUp = true
            cookAssigned = true
        }
    }

    private func pause(_ milliseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

/// A pasted link becoming a recipe, then a bookmark. It is deliberately a
/// shell, not a fake form: the tour demonstrates the result without putting
/// dead controls under somebody's thumb.
struct TourRecipeSave: View {
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shellVisible = false
    @State private var addressVisible = false
    @State private var importProgress: CGFloat = 0
    @State private var recipeVisible = false
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ADD A RECIPE")
                    .plType(.micro, .bold)
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "viewfinder")
                    Text("SCAN")
                }
                .font(.sans(10, .bold))
                .foregroundStyle(Color.inkSecondary)
                .plChrome()
            }

            HStack(spacing: 9) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
                Text("weeknight.kitchen/lemon-orzo")
                    .plType(.caption, .medium)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .opacity(addressVisible ? 1 : 0)
                    .offset(x: addressVisible ? 0 : 8)
                Spacer(minLength: 4)
                Text(importProgress < 1 ? "IMPORT" : "DONE")
                    .plType(.micro, .bold)
                    .foregroundStyle(importProgress < 1 ? Color.accentText : Color.completion)
                    .plChrome()
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.fill, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.olive)
                        .frame(width: max(0, proxy.size.width - 8) * importProgress, height: 2)
                        .padding(.horizontal, 4)
                }
                .frame(height: 2)
            }

            HStack(spacing: 11) {
                TourFoodPhoto(asset: "TourSalad", width: 70, height: 58, radius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Lemon orzo")
                        .plType(.body, .bold)
                        .foregroundStyle(Color.ink)
                    Text("Imported just now")
                        .plType(.caption, .medium)
                        .foregroundStyle(Color.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 3) {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(saved ? Color.olive : Color.inkSecondary)
                        .scaleEffect(saved ? 1.08 : 1)
                    Text(saved ? "SAVED" : "SAVE")
                        .plType(.micro, .bold)
                        .foregroundStyle(saved ? Color.olive : Color.inkSecondary)
                        .plChrome()
                }
            }
            .padding(10)
            .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            }
            .scaleEffect(recipeVisible ? 1 : 0.94, anchor: .top)
            .offset(y: recipeVisible ? 0 : 8)
            .opacity(recipeVisible ? 1 : 0)
        }
        .padding(14)
        .frame(maxWidth: 330)
        .background(Color.cardFill, in: Radius.shape(Radius.card))
        .overlay {
            Radius.shape(Radius.card)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
        .plCardShadow()
        .scaleEffect(shellVisible ? 1 : 0.95)
        .offset(y: shellVisible ? 0 : 18)
        .opacity(shellVisible ? 1 : 0)
        .plChrome()
        .task(id: isActive) { await play() }
        .accessibilityHidden(true)
    }

    @MainActor
    private func play() async {
        reset()
        guard isActive else { return }
        guard !reduceMotion else {
            finish()
            return
        }

        guard await pause(70) else { return }
        withAnimation(.plSettle) { shellVisible = true }
        guard await pause(150) else { return }
        withAnimation(.plSnap) { addressVisible = true }
        guard await pause(130) else { return }
        withAnimation(.easeInOut(duration: 0.42)) { importProgress = 1 }
        guard await pause(430) else { return }
        withAnimation(.plSettle) { recipeVisible = true }
        guard await pause(210) else { return }
        withAnimation(.plPop) { saved = true }
    }

    @MainActor
    private func reset() {
        withAnimation(nil) {
            shellVisible = false
            addressVisible = false
            importProgress = 0
            recipeVisible = false
            saved = false
        }
    }

    @MainActor
    private func finish() {
        withAnimation(nil) {
            shellVisible = true
            addressVisible = true
            importProgress = 1
            recipeVisible = true
            saved = true
        }
    }

    private func pause(_ milliseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

/// A compact Table post with all three social signals in view: plates,
/// conversation and a recipe saved for later. The post lands first, then
/// those responses happen in the order somebody would make them.
struct TourTablePost: View {
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardVisible = false
    @State private var photoVisible = false
    @State private var reacted = false
    @State private var commentsShown = 0
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                AvatarCircle(initials: "A", tone: .tomatoPair, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Alex")
                        .plType(.caption, .bold)
                        .foregroundStyle(Color.ink)
                    Text("Tonight")
                        .plType(.micro, .medium)
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Text("AT THE TABLE")
                    .plType(.micro, .bold)
                    .foregroundStyle(Color.inkSecondary)
                    .plChrome()
            }

            HStack(spacing: 10) {
                TourFoodPhoto(asset: "TourPasta", width: 72, height: 54, radius: 12)
                    .scaleEffect(photoVisible ? 1 : 0.82)
                    .opacity(photoVisible ? 1 : 0)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Crispy olive gnocchi")
                        .plType(.body, .bold)
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                    Text("First try. Definitely making it again.")
                        .plType(.micro, .medium)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                }
            }

            Divider().overlay(Color.hairline)

            HStack(spacing: 15) {
                HStack(spacing: 5) {
                    PlateReactionGlyph(filled: reacted, size: 20)
                        .scaleEffect(reacted ? 1.12 : 1)
                    Text(reacted ? "4" : "3")
                        .plType(.micro, .bold)
                        .foregroundStyle(Color.inkSecondary)
                }
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("2")
                        .plType(.micro, .bold)
                }
                .foregroundStyle(Color.inkSecondary)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .semibold))
                    Text(saved ? "Saved" : "Save")
                        .plType(.micro, .bold)
                }
                .foregroundStyle(saved ? Color.olive : Color.inkSecondary)
                .scaleEffect(saved ? 1.04 : 1)
            }
            .plChrome()

            comment(initials: "M", tone: .grapePair, name: "Maya", text: "Need this recipe.")
                .opacity(commentsShown >= 1 ? 1 : 0)
                .offset(x: commentsShown >= 1 ? 0 : 10)
            comment(initials: "N", tone: .basilPair, name: "Noah", text: "That plate looks perfect.")
                .opacity(commentsShown >= 2 ? 1 : 0)
                .offset(x: commentsShown >= 2 ? 0 : 10)
        }
        .padding(12)
        .frame(maxWidth: 330)
        .background(Color.cardFill, in: Radius.shape(Radius.card))
        .overlay {
            Radius.shape(Radius.card)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
        .plCardShadow()
        .scaleEffect(cardVisible ? 1 : 0.94)
        .offset(y: cardVisible ? 0 : 20)
        .opacity(cardVisible ? 1 : 0)
        .plChrome()
        .task(id: isActive) { await play() }
        .accessibilityHidden(true)
    }

    private func comment(initials: String, tone: PersonTone, name: String, text: String) -> some View {
        HStack(spacing: 6) {
            AvatarCircle(initials: initials, tone: tone, size: 18)
            (Text(name + "  ").fontWeight(.bold) + Text(text))
                .plType(.micro, .medium)
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
        }
    }

    @MainActor
    private func play() async {
        reset()
        guard isActive else { return }
        guard !reduceMotion else {
            finish()
            return
        }

        guard await pause(70) else { return }
        withAnimation(.plSettle) { cardVisible = true }
        guard await pause(170) else { return }
        withAnimation(.plPop) { photoVisible = true }
        guard await pause(190) else { return }
        withAnimation(.plPop) { reacted = true }
        guard await pause(160) else { return }
        withAnimation(.plSnap) { commentsShown = 1 }
        guard await pause(130) else { return }
        withAnimation(.plSnap) { commentsShown = 2 }
        guard await pause(170) else { return }
        withAnimation(.plPop) { saved = true }
    }

    @MainActor
    private func reset() {
        withAnimation(nil) {
            cardVisible = false
            photoVisible = false
            reacted = false
            commentsShown = 0
            saved = false
        }
    }

    @MainActor
    private func finish() {
        withAnimation(nil) {
            cardVisible = true
            photoVisible = true
            reacted = true
            commentsShown = 2
            saved = true
        }
    }

    private func pause(_ milliseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

/// Recipe and post photographs keep the rounded-rectangle grammar of the
/// real product. The generated dish is a last-resort fallback if an optional
/// tour photograph is not in the bundle.
private struct TourFoodPhoto: View {
    let asset: String
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(named: asset) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.fill
                    .overlay {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.inkSecondary)
                    }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A plate on the tour: the photograph if it is in the bundle, the drawn
/// dish if it is not.
///
/// The fallback is the point. The four food photographs are installed by
/// `scripts/tour-photos`, and until they are there this draws exactly what
/// the tour drew before them, so a missing asset is never an empty circle
/// on the first screen somebody sees.
struct TourPlate: View {
    let asset: String
    let fallbackTitle: String
    var diameter: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(named: asset) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                    .overlay {
                        // The porcelain rim the plan's own plates wear, so a
                        // photograph reads as a dish rather than a sticker.
                        Circle().strokeBorder(Color.canvas, lineWidth: diameter * 0.055)
                    }
            } else {
                DishView(title: fallbackTitle, diameter: diameter)
            }
        }
        .plDishShadow()
    }
}
