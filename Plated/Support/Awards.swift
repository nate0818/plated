import Foundation

enum AwardTone: String, CaseIterable {
    case tomato, amber, basil, grape, copper, cocoa
}

enum AwardTier: String {
    case first = "First"
    case bronze = "Bronze"
    case silver = "Silver"
    case gold = "Gold"
}

struct AwardMetrics: Equatable {
    var cookedMeals = 0
    var distinctDishesCooked = 0
    var activeCookWeeks = 0
    var fullestPlannedWeek = 0
    var cookbookRecipes = 0
    var tablePosts = 0
    var happyPlates = 0
    var chefsKisses = 0
    var savesReceived = 0
    var householdPeople = 0
}

struct PlatedAward: Identifiable, Equatable {
    let id: String
    let title: String
    let story: String
    let howToEarn: String
    let symbol: String
    let tone: AwardTone
    let tier: AwardTier
    let current: Int
    let goal: Int
    let points: Int
    let earnedAt: Date?

    var isEarned: Bool { current >= goal }
    var progress: Double { min(1, Double(current) / Double(max(1, goal))) }
    var progressLine: String {
        isEarned ? "Earned" : "\(min(current, goal)) of \(goal)"
    }
}

struct KitchenStanding: Equatable {
    let title: String
    let score: Int
    let nextTitle: String?
    let nextScore: Int?
    let progress: Double
}

/// The quiet scorekeeper. Counts the moments worth counting — saves your
/// dishes earn from the table, kisses, firsts — so Home can show them off.
/// Local UserDefaults today; becomes server-side when the network arrives.
enum Awards {
    private static let savesKey = "awards.savesReceived"
    private static let earnedKey = "awards.earnedDates.v2"

    private struct Definition {
        let id: String
        let title: String
        let story: String
        let howToEarn: String
        let symbol: String
        let tone: AwardTone
        let tier: AwardTier
        let goal: Int
        let points: Int
        let value: (AwardMetrics) -> Int
    }

    private static let definitions: [Definition] = [
        Definition(
            id: "first-plate", title: "First plate",
            story: "The first dinner you finished with Plated.",
            howToEarn: "Cook one planned dish.", symbol: "fork.knife",
            tone: .tomato, tier: .first, goal: 1, points: 75,
            value: { $0.cookedMeals }
        ),
        Definition(
            id: "week-set", title: "Week set",
            story: "A full week took shape before dinner had to ask.",
            howToEarn: "Plan five meals in one calendar week.", symbol: "calendar.badge.checkmark",
            tone: .copper, tier: .bronze, goal: 5, points: 125,
            value: { $0.fullestPlannedWeek }
        ),
        Definition(
            id: "kitchen-regular", title: "Kitchen regular",
            story: "Ten dinners made this kitchen a rhythm.",
            howToEarn: "Cook 10 planned meals.", symbol: "flame.fill",
            tone: .amber, tier: .bronze, goal: 10, points: 175,
            value: { $0.cookedMeals }
        ),
        Definition(
            id: "taste-explorer", title: "Taste explorer",
            story: "Five different dishes, each given a real night at the table.",
            howToEarn: "Cook five different recipes.", symbol: "safari.fill",
            tone: .basil, tier: .bronze, goal: 5, points: 175,
            value: { $0.distinctDishesCooked }
        ),
        Definition(
            id: "cookbook-builder", title: "Cookbook builder",
            story: "A dozen recipes worth returning to.",
            howToEarn: "Build a cookbook of 12 recipes.", symbol: "books.vertical.fill",
            tone: .cocoa, tier: .silver, goal: 12, points: 225,
            value: { $0.cookbookRecipes }
        ),
        Definition(
            id: "table-voice", title: "Table voice",
            story: "You brought a dish or a question to the conversation.",
            howToEarn: "Share three posts at the Table.", symbol: "bubble.left.and.bubble.right.fill",
            tone: .grape, tier: .bronze, goal: 3, points: 150,
            value: { $0.tablePosts }
        ),
        Definition(
            id: "crowd-pleaser", title: "Crowd pleaser",
            story: "Ten happy plates landed on food you shared.",
            howToEarn: "Receive 10 happy plates on your Table posts.", symbol: "hands.clap.fill",
            tone: .tomato, tier: .silver, goal: 10, points: 250,
            value: { $0.happyPlates }
        ),
        Definition(
            id: "chefs-kiss", title: "Chef's kiss",
            story: "One plate became a household favorite.",
            howToEarn: "Earn a Chef's Kiss on one Table post.", symbol: "seal.fill",
            tone: .amber, tier: .gold, goal: 1, points: 350,
            value: { $0.chefsKisses }
        ),
        Definition(
            id: "passed-around", title: "Passed around",
            story: "Something you shared became part of another cookbook.",
            howToEarn: "Have five shared dishes saved by others.", symbol: "square.and.arrow.down.fill",
            tone: .copper, tier: .silver, goal: 5, points: 275,
            value: { $0.savesReceived }
        ),
        Definition(
            id: "dinner-ritual", title: "Dinner ritual",
            story: "Four different weeks carry a dinner you made.",
            howToEarn: "Cook in four separate calendar weeks. They do not need to be consecutive.",
            symbol: "circle.grid.2x2.fill", tone: .basil, tier: .silver,
            goal: 4, points: 250, value: { $0.activeCookWeeks }
        ),
        Definition(
            id: "full-table", title: "Full table",
            story: "Planning became something the household shares.",
            howToEarn: "Bring three people into your household.", symbol: "person.3.fill",
            tone: .grape, tier: .gold, goal: 3, points: 300,
            value: { $0.householdPeople }
        ),
        Definition(
            id: "house-legend", title: "House legend",
            story: "Fifty dinners. A real archive of ordinary nights made memorable.",
            howToEarn: "Cook 50 planned meals.", symbol: "trophy.fill",
            tone: .cocoa, tier: .gold, goal: 50, points: 600,
            value: { $0.cookedMeals }
        )
    ]

    /// "Sam Meadows" the author and "Sam" the comment name are the same
    /// person — first name, lowercased, is the ledger key until real user
    /// IDs exist. Known trade-off: two people who share a first name share
    /// a ledger line; real IDs (the network) dissolve this.
    private static func normalize(_ name: String) -> String {
        name.split(separator: " ").first.map { $0.lowercased() } ?? name.lowercased()
    }

    /// Turns product activity into a compact set of award inputs. An
    /// assigned meal belongs only to its cook. An unassigned one belongs to
    /// whoever planned it (`authorID`), and to the head of table only when
    /// the row predates that field, because older builds stored neither a
    /// cook nor an author. Recipes are the same: the author's, and an
    /// unattributed one is the reader's, since it was written on the phone
    /// that is reading it. `ownerFallback` vouches that a nil `person` is
    /// the reader.
    @MainActor
    static func metrics(
        for person: HouseholdMember?,
        meals: [PlannedMeal],
        recipes: [Recipe],
        posts: [TablePost],
        householdSize: Int,
        ownerFallback: Bool = true
    ) -> AwardMetrics {
        let personName = person?.name ?? "Me"
        let personKey = normalize(personName)
        let isMe = person?.isMe ?? ownerFallback
        let isHead = person?.isOwner ?? ownerFallback
        // The identity an `authorID` is compared against: the row's own when
        // it carries one, else this phone's when the row is the reader's.
        let identity: String? = {
            if let id = person?.userRecordName, !id.isEmpty { return id }
            return isMe ? TableIdentity.cached : nil
        }()
        func owns(unassigned authorID: String) -> Bool {
            authorID.isEmpty ? isHead : authorID == identity
        }
        func wrote(_ authorID: String) -> Bool {
            authorID.isEmpty ? isMe : authorID == identity
        }
        let cooked = meals.filter { meal in
            guard meal.cookedAt != nil else { return false }
            if let cook = meal.cook { return normalize(cook.name) == personKey }
            return owns(unassigned: meal.authorID)
        }
        let planned = meals.filter { meal in
            if let cook = meal.cook { return normalize(cook.name) == personKey }
            return owns(unassigned: meal.authorID)
        }
        let authored = posts.filter {
            !$0.isDiscover && $0.isUserContent && normalize($0.authorName) == personKey
        }

        let calendar = Calendar.current
        let cookedWeeks = Set(cooked.compactMap { meal -> DateComponents? in
            guard let date = meal.cookedAt else { return nil }
            return calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        })
        let weekCounts = Dictionary(grouping: planned) { meal in
            calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: meal.date)
        }
        let dishNames = Set(cooked.map { meal in
            (meal.recipe?.title ?? meal.title)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }.filter { !$0.isEmpty })

        return AwardMetrics(
            cookedMeals: cooked.count,
            distinctDishesCooked: dishNames.count,
            activeCookWeeks: cookedWeeks.count,
            fullestPlannedWeek: weekCounts.values.map(\.count).max() ?? 0,
            cookbookRecipes: recipes.filter { wrote($0.authorID) }.count,
            tablePosts: authored.count,
            happyPlates: authored.reduce(0) { $0 + $1.totalPlates },
            chefsKisses: authored.filter { $0.hasChefsKiss(seats: householdSize) }.count,
            savesReceived: savesReceived(by: personName),
            householdPeople: householdSize
        )
    }

    /// Evaluating awards is also the moment newly earned dates are recorded.
    /// Progress can move; earned dates cannot. Awards never disappear if a
    /// post is later removed or the household changes shape.
    static func evaluate(_ metrics: AwardMetrics, for personName: String) -> [PlatedAward] {
        let prefix = normalize(personName) + "."
        var earned = UserDefaults.standard.dictionary(forKey: earnedKey) as? [String: Double] ?? [:]
        var changed = false
        let now = Date.now.timeIntervalSince1970

        let result = definitions.map { definition -> PlatedAward in
            let value = max(0, definition.value(metrics))
            let key = prefix + definition.id
            if value >= definition.goal, earned[key] == nil {
                earned[key] = now
                changed = true
            }
            return PlatedAward(
                id: definition.id,
                title: definition.title,
                story: definition.story,
                howToEarn: definition.howToEarn,
                symbol: definition.symbol,
                tone: definition.tone,
                tier: definition.tier,
                current: value,
                goal: definition.goal,
                points: definition.points,
                earnedAt: earned[key].map(Date.init(timeIntervalSince1970:))
            )
        }
        if changed { UserDefaults.standard.set(earned, forKey: earnedKey) }
        return result
    }

    static func standing(for awards: [PlatedAward]) -> KitchenStanding {
        let score = awards.filter(\.isEarned).reduce(0) { $0 + $1.points }
        let levels: [(score: Int, title: String)] = [
            (0, "Prep cook"),
            (150, "Home cook"),
            (500, "Table maker"),
            (1_000, "Kitchen anchor"),
            (1_750, "House legend")
        ]
        let current = levels.last(where: { score >= $0.score }) ?? levels[0]
        guard let index = levels.firstIndex(where: { $0.score == current.score }),
              levels.indices.contains(index + 1) else {
            return KitchenStanding(title: current.title, score: score, nextTitle: nil, nextScore: nil, progress: 1)
        }
        let next = levels[index + 1]
        let span = max(1, next.score - current.score)
        return KitchenStanding(
            title: current.title,
            score: score,
            nextTitle: next.title,
            nextScore: next.score,
            progress: min(1, Double(score - current.score) / Double(span))
        )
    }

    /// Counts recorded before normalization existed were keyed by full
    /// name; fold them into their normalized keys once so nobody's earned
    /// saves read as zero after an update.
    private static func rekeyIfNeeded() {
        let flag = "awards.rekeyed.v1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        let counts = UserDefaults.standard.dictionary(forKey: savesKey) as? [String: Int] ?? [:]
        guard !counts.isEmpty else { return }
        var folded: [String: Int] = [:]
        for (key, value) in counts {
            folded[normalize(key), default: 0] += value
        }
        UserDefaults.standard.set(folded, forKey: savesKey)
    }

    /// Someone plated a dish from `author`'s post into their cookbook.
    static func recordSaveReceived(by author: String) {
        rekeyIfNeeded()
        var counts = UserDefaults.standard.dictionary(forKey: savesKey) as? [String: Int] ?? [:]
        counts[normalize(author), default: 0] += 1
        UserDefaults.standard.set(counts, forKey: savesKey)
    }

    static func savesReceived(by author: String) -> Int {
        rekeyIfNeeded()
        let counts = UserDefaults.standard.dictionary(forKey: savesKey) as? [String: Int] ?? [:]
        return counts[normalize(author)] ?? 0
    }

    static var totalSavesRecorded: Int {
        let counts = UserDefaults.standard.dictionary(forKey: savesKey) as? [String: Int] ?? [:]
        return counts.values.reduce(0, +)
    }

    /// Carry a ledger line to a new name. The ledger is keyed by first
    /// name, so someone renaming themselves would otherwise walk away from
    /// every save they had earned — the counter silently resets to zero and
    /// looks like the awards were never recorded.
    ///
    /// Merges rather than overwrites: if the new key already has a line
    /// (a rename onto a name that once belonged to someone else here), the
    /// totals add rather than one erasing the other.
    static func rekey(from oldName: String, to newName: String) {
        rekeyIfNeeded()
        let from = normalize(oldName), to = normalize(newName)
        guard from != to else { return }
        var counts = UserDefaults.standard.dictionary(forKey: savesKey) as? [String: Int] ?? [:]
        if let moving = counts.removeValue(forKey: from), moving > 0 {
            counts[to, default: 0] += moving
            UserDefaults.standard.set(counts, forKey: savesKey)
        }

        var dates = UserDefaults.standard.dictionary(forKey: earnedKey) as? [String: Double] ?? [:]
        let oldPrefix = from + ".", newPrefix = to + "."
        let movingDates = dates.filter { $0.key.hasPrefix(oldPrefix) }
        for (key, date) in movingDates {
            dates[key] = nil
            let id = String(key.dropFirst(oldPrefix.count))
            let destination = newPrefix + id
            dates[destination] = min(dates[destination] ?? date, date)
        }
        UserDefaults.standard.set(dates, forKey: earnedKey)
    }
}
