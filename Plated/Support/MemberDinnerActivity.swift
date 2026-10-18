import Foundation

/// Logged household activity, attributed to the cook rather than the planner.
/// Shared records remain a read-only overlay, with local echoes taking priority.
@MainActor
struct MemberDinnerActivity {
    let cooked: Int
    let shared: Int

    init(member: HouseholdMember, roster: [HouseholdMember], meals: [PlannedMeal],
         remote: [PlanLedger.Entry], posts: [TablePost], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        var dinners: [String: Bool] = [:]
        for entry in remote where entry.slot == MealSlot.dinner.rawValue {
            let key = entry.shoppingID.isEmpty ? entry.recordName : "plan-" + entry.shoppingID
            let isCook = !entry.cookID.isEmpty && PlanRowVoice.member(id: entry.cookID, in: roster)?.persistentModelID == member.persistentModelID
            let date = PlanDay.date(entry.day)
            dinners[key] = isCook && entry.cooked && !entry.isGoing
                && !PlanRowVoice.isEatingOut(title: entry.title, hasRecipe: entry.hasRecipe)
                && date.map { $0 >= start && $0 < end } == true
        }
        for meal in meals where !meal.isDeleted && meal.slotValue == .dinner {
            let key = meal.shoppingID.flatMap { $0.isEmpty ? nil : "plan-" + $0 }
                ?? String(describing: meal.persistentModelID)
            dinners[key] = meal.cook?.persistentModelID == member.persistentModelID && meal.isCooked
                && !PlanRowVoice.isEatingOut(title: meal.title, hasRecipe: meal.recipe != nil)
                && meal.date >= start && meal.date < end
        }
        cooked = dinners.values.filter { $0 }.count
        var postIDs = Set<String>()
        for post in posts where !post.isDeleted && post.isUserContent && !post.isDiscover
            && post.kind != "ask" && post.createdAt >= start && post.createdAt <= now {
            guard ProfileIdentity.matches(authorID: post.authorID, authorName: post.authorName,
                member: member, profileName: member.name, roster: roster) else { continue }
            postIDs.insert(post.shareRecordName.isEmpty ? String(describing: post.persistentModelID) : post.shareRecordName)
        }
        shared = postIDs.count
    }

    var summary: String {
        if cooked == 0 && shared == 0 { return "No activity recorded in the last 7 days." }
        return "\(cooked) \(cooked == 1 ? "dinner" : "dinners") cooked · \(shared) \(shared == 1 ? "post" : "posts") shared"
    }
}
