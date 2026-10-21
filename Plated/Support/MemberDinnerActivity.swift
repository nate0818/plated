import Foundation

/// Logged household activity, attributed to the cook rather than the planner.
/// Shared records remain a read-only overlay, with local echoes taking priority.
@MainActor
struct MemberDinnerActivity {
    let cooked: Int
    let shared: Int
    struct Event {
        let line: String
        let date: Date
    }
    let latest: Event?

    init(member: HouseholdMember, roster: [HouseholdMember], meals: [PlannedMeal],
         remote: [PlanLedger.Entry], posts: [TablePost], now: Date = .now, calendar: Calendar = .current,
         lookbackDays: Int? = 7) {
        let today = calendar.startOfDay(for: now)
        let start = lookbackDays.map { calendar.date(byAdding: .day, value: -(max(1, $0) - 1), to: today) ?? today }
            ?? Date.distantPast
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        var dinners: [String: Bool] = [:]
        var events: [String: Event] = [:]
        for entry in remote where entry.slot == MealSlot.dinner.rawValue {
            let key = entry.shoppingID.isEmpty ? entry.recordName : "plan-" + entry.shoppingID
            let isCook = !entry.cookID.isEmpty && PlanRowVoice.member(id: entry.cookID, in: roster)?.persistentModelID == member.persistentModelID
            let date = PlanDay.date(entry.day)
            dinners[key] = isCook && entry.cooked && !entry.isGoing
                && !PlanRowVoice.isEatingOut(title: entry.title, hasRecipe: entry.hasRecipe)
                && !PlanRowVoice.isLeftovers(title: entry.title, hasRecipe: entry.hasRecipe)
                && date.map { $0 >= start && $0 < end } == true
            if dinners[key] == true, let date {
                events[key] = Event(line: "Cooked \(entry.title.isEmpty ? "dinner" : entry.title)", date: entry.cookedAt ?? date)
            } else { events.removeValue(forKey: key) }
        }
        for meal in meals where !meal.isDeleted && meal.slotValue == .dinner {
            let key = meal.shoppingID.flatMap { $0.isEmpty ? nil : "plan-" + $0 }
                ?? String(describing: meal.persistentModelID)
            dinners[key] = meal.cook?.persistentModelID == member.persistentModelID && meal.isCooked
                && !PlanRowVoice.isEatingOut(title: meal.title, hasRecipe: meal.recipe != nil)
                && !meal.isLeftovers
                && meal.date >= start && meal.date < end
            if dinners[key] == true {
                events[key] = Event(line: "Cooked \(meal.title)", date: meal.cookedAt ?? meal.date)
            } else { events.removeValue(forKey: key) }
        }
        cooked = dinners.values.filter { $0 }.count
        var postIDs = Set<String>()
        for post in posts where !post.isDeleted && post.isUserContent && !post.isDiscover
            && post.kind != "ask" && post.createdAt >= start && post.createdAt <= now {
            guard ProfileIdentity.matches(authorID: post.authorID, authorName: post.authorName,
                member: member, profileName: member.name, roster: roster) else { continue }
            let key = post.shareRecordName.isEmpty ? String(describing: post.persistentModelID) : post.shareRecordName
            postIDs.insert(key)
            events["post-" + key] = Event(line: post.dishTitle.isEmpty ? "Shared a post at the Table" : "Shared \(post.dishTitle)", date: post.createdAt)
        }
        shared = postIDs.count
        latest = events.values.filter { $0.date <= now }.max { $0.date < $1.date }
    }

    var summary: String {
        if cooked == 0 && shared == 0 { return "No activity recorded in the last 7 days." }
        return "\(cooked) \(cooked == 1 ? "dinner" : "dinners") cooked · \(shared) \(shared == 1 ? "post" : "posts") shared"
    }
}

/// Plan's recent events can include planning, without counting a planned
/// dinner as cooked or attributing its author’s action to the assigned cook.
@MainActor
struct PlanMemberEvent {
    let line: String
    let date: Date
    let dinnerDate: Date?

    static func latest(member: HouseholdMember, roster: [HouseholdMember], meals: [PlannedMeal],
                       remote: [PlanLedger.Entry], recorded: MemberDinnerActivity.Event?,
                       now: Date = .now, calendar: Calendar = .current) -> Self? {
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        var events: [Self] = recorded.map { [Self(line: $0.line, date: $0.date, dinnerDate: nil)] } ?? []
        let localIDs = Set(meals.filter { !$0.isDeleted }.compactMap(\.shoppingID))
        for meal in meals where !meal.isDeleted && meal.hasDish && !meal.isCooked
            && meal.createdAt >= start && meal.createdAt <= now {
            // Like PlanRowVoice, an unstamped private meal belongs to the
            // current account. Its assigned cook may be someone else.
            let isAuthor = meal.authorID.isEmpty ? member.isMe : ProfileIdentity.matches(authorID: meal.authorID, authorName: "", member: member,
                profileName: member.name, roster: roster)
            guard isAuthor else { continue }
            events.append(Self(line: "Planned \(meal.title)", date: meal.createdAt, dinnerDate: meal.date))
        }
        for entry in remote where entry.hasDish && !entry.cooked && entry.pendingSince == nil
            && !localIDs.contains(entry.shoppingID) && entry.changedAt >= start && entry.changedAt <= now {
            guard ProfileIdentity.matches(authorID: entry.changedByID, authorName: "", member: member,
                profileName: member.name, roster: roster) else { continue }
            let verb = entry.changedAt.timeIntervalSince(entry.createdAt) < 1 ? "Planned" : "Updated"
            events.append(Self(line: "\(verb) \(entry.title)", date: entry.changedAt, dinnerDate: entry.date))
        }
        return events.max { $0.date < $1.date }
    }
}
