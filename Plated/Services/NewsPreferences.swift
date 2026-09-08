import Foundation

/// What the Table may say out loud, and about which dishes.
///
/// Every switch here decides whether a notice lights the screen. None of
/// them decides whether the bell keeps the row: the list is a record of
/// what happened, and a person who muted a dish still gets to read about
/// it when they choose to. This is what Messages, Slack and WhatsApp all
/// agree on, and it is the shape a person reaches for right before they
/// turn everything off in iOS Settings, so it is worth getting right.
///
/// Two rules survive every switch:
///
/// - **A word to you is always a word to you.** A reply, a mention or a
///   tag gets through a muted dish. Only the Replies switch can silence
///   it, and that switch says so.
/// - **Off is quiet, not blind.** The rows are still written, the badge
///   stops counting them, and the caption in Settings says exactly that.
@MainActor
enum NewsPreferences {

    /// The categories that actually exist in the pipe. Planning joined when
    /// the plan started crossing Apple IDs through the shared zone
    /// (docs/plan-share.md); grocery notices still do not, so there is no
    /// switch for them. A switch for a notice that can never fire is a lie
    /// about what the app can do.
    enum Category: String, CaseIterable {
        case dishes
        case replies
        case comments
        case plates
        case seats
        case planning

        var key: String { "tableNews.\(rawValue)" }

        var title: String {
            switch self {
            case .dishes: return "Dishes and asks"
            case .replies: return "Replies and mentions"
            case .comments: return "Comments on yours"
            case .plates: return "Plates and votes on yours"
            case .seats: return "New seats"
            case .planning: return "Planning"
            }
        }

        /// The row's caption when the switch is on.
        var detail: String {
            switch self {
            case .dishes: return "When somebody plates a dish or asks the table"
            case .replies: return "A reply to you, your name, or a tag. Gets through a muted dish."
            case .comments: return "When somebody writes on a dish you plated"
            case .plates: return "Quiet: in the list and on the icon, never a banner"
            case .seats: return "When an invitation is accepted"
            case .planning: return "When somebody plans a night, moves it, or takes it off the week"
            }
        }

        var symbol: String {
            switch self {
            case .dishes: return "fork.knife"
            case .replies: return "arrowshape.turn.up.left"
            case .comments: return "bubble.right"
            case .plates: return "circle.circle"
            case .seats: return "person.badge.plus"
            case .planning: return "calendar"
            }
        }
    }

    private static let mutedKey = "plated.news.muted"

    /// Shared with the widget and the notification pipe, like the seen keys.
    private static var store: UserDefaults {
        UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
    }

    // MARK: The master switch

    /// The Settings switch that existed first. Off means nothing from the
    /// Table lights the screen and the icon stops counting.
    static var tableOn: Bool {
        get { UserDefaults.standard.object(forKey: TableNews.tableOnKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: TableNews.tableOnKey) }
    }

    // MARK: Categories

    /// Defaults on. `object(forKey:) == nil` is on, so a switch nobody has
    /// touched reads as the app has always behaved.
    static func isOn(_ category: Category) -> Bool {
        UserDefaults.standard.object(forKey: category.key) as? Bool ?? true
    }

    static func set(_ category: Category, on: Bool) {
        UserDefaults.standard.set(on, forKey: category.key)
    }

    /// Which switch governs a notice. A dish you were tagged in, and a
    /// reply or mention, are words to you and live under Replies whatever
    /// the record type; the kiss is a plate. A plan notice is about a
    /// night, never a word to you, so it answers to Planning before the
    /// addressed question is even asked: "put you down to cook" is what
    /// somebody did to the week, and the switch for the week governs it.
    static func category(for kind: TableNews.Notice.Kind, addressed: Bool) -> Category {
        if kind == .plan { return .planning }
        if addressed { return .replies }
        switch kind {
        case .dish, .ask, .more: return .dishes
        case .comment: return .comments
        case .plates, .kiss, .votes: return .plates
        case .seat: return .seats
        case .plan: return .planning
        // The household's own notices (docs/household.md section 10) answer
        // to the same six switches: the coarse "Household and Table
        // activity" already covers both rooms, and a seventh switch for a
        // second kind of seat would be a switch nobody goes looking for.
        case .householdSeat, .householdLeft: return .seats
        // A recipe joining the cookbook is the nearest the household has to
        // a dish being put out. There is no cookbook switch.
        case .recipe: return .dishes
        // Bell only, so `TableNews.select` drops it before the screen and
        // this answer is never acted on. It rides with the night rather
        // than claiming a switch of its own.
        case .conflict: return .planning
        }
    }

    /// The same question asked of a bell row, for the icon's count.
    static func category(for kind: PlatedNotificationKind, addressed: Bool) -> Category? {
        if kind == .planShared { return .planning }
        if addressed { return .replies }
        switch kind {
        case .dishPosted, .askPosted: return .dishes
        case .commentAdded: return .comments
        case .plateReaction, .voteCast: return .plates
        case .seatJoined: return .seats
        case .planShared: return .planning
        default: return nil
        }
    }

    // MARK: Muting a dish

    static func mutedPosts() -> Set<String> {
        Set(store.stringArray(forKey: mutedKey) ?? [])
    }

    static func isMuted(post record: String) -> Bool {
        !record.isEmpty && mutedPosts().contains(record)
    }

    /// Silent to everyone else, the way every messaging app does it. The
    /// author never learns, and nothing about the dish changes.
    static func setMuted(post record: String, _ muted: Bool) {
        guard !record.isEmpty else { return }
        var all = mutedPosts()
        if muted { all.insert(record) } else { all.remove(record) }
        store.set(Array(all).sorted(), forKey: mutedKey)
        print("[News] \(muted ? "muted" : "unmuted") \(record)")
    }

    /// For tests.
    static func reset() {
        store.removeObject(forKey: mutedKey)
        for category in Category.allCases {
            UserDefaults.standard.removeObject(forKey: category.key)
        }
    }

    // MARK: The decision

    /// Whether this notice may reach the screen at all. The master switch
    /// and iOS permission are checked by the caller; this is the person's
    /// finer answer.
    static func allows(_ notice: TableNews.Notice) -> Bool {
        allows(kind: notice.kind, addressed: notice.addressed, post: notice.post)
    }

    static func allows(kind: TableNews.Notice.Kind, addressed: Bool, post: String) -> Bool {
        let category = category(for: kind, addressed: addressed)
        guard isOn(category) else { return false }
        // A muted dish is muted for the room's chatter about it. A word
        // addressed to you is not the room's chatter.
        if isMuted(post: post) && !addressed { return false }
        return true
    }

    /// Whether an unread bell row should count on the icon. Rows about
    /// your own actions never did; rows in a category you turned off, or
    /// about a dish you muted, stop too, because a badge that nags about
    /// something you asked not to hear about is the nag by another door.
    static func counts(_ row: PlatedNotification) -> Bool {
        guard !row.eventKey.isEmpty else { return false }
        guard let category = category(for: row.kindValue, addressed: row.addressed) else { return true }
        guard isOn(category) else { return false }
        if let url = row.linkURL, let post = DeepLink.postID(in: url),
           isMuted(post: post), !row.addressed {
            return false
        }
        return true
    }
}
