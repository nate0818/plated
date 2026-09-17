import Foundation
import SwiftData

/// The one conversational line under a filled Plan meal title.
///
/// Nate-approved Plan craft 2026-09-17: avatar + who-line, never `{Name}
/// cooks`, never eat-out reportage ("said we're…"), never eng chips.
/// Cooking is a role sentence; eat-out is a quote-style declaration.
/// One line per row. The strings live here so the week list, Tonight card,
/// remote row, and the tests that pin them cannot drift.
enum PlanRowVoice {

    /// Who the who-line is about, so the face and the sentence name the
    /// same person.
    struct Actor: Equatable {
        var isYou: Bool
        var firstName: String
    }

    enum Kind: Equatable {
        /// Cook assigned — `{Name} is cooking` / `You're cooking`.
        case cooking
        /// Night planned, cook not the point — `{Name} planned this night`.
        case planned
        /// Eat-out night type — `{Name}: we're eating out`.
        case eatOut
    }

    static func isEatingOut(title: String, hasRecipe: Bool) -> Bool {
        !hasRecipe && title.localizedCaseInsensitiveContains("eating out")
    }

    static func kind(eatingOut: Bool, hasCook: Bool) -> Kind {
        if eatingOut { return .eatOut }
        if hasCook { return .cooking }
        return .planned
    }

    /// Eat-out speaks as the cook when one is named, otherwise the planner.
    /// Cooking names the cook. Planned names the planner.
    static func actor(
        eatingOut: Bool,
        hasCook: Bool,
        cookIsYou: Bool,
        cookFirstName: String,
        plannerIsYou: Bool,
        plannerFirstName: String
    ) -> Actor {
        if eatingOut {
            return hasCook
                ? Actor(isYou: cookIsYou, firstName: cookFirstName)
                : Actor(isYou: plannerIsYou, firstName: plannerFirstName)
        }
        if hasCook {
            return Actor(isYou: cookIsYou, firstName: cookFirstName)
        }
        return Actor(isYou: plannerIsYou, firstName: plannerFirstName)
    }

    /// Identity and name of the person the face belongs to, matching `actor`.
    static func speakerID(
        eatingOut: Bool, hasCook: Bool, cookID: String, authorID: String
    ) -> String {
        let kind = kind(eatingOut: eatingOut, hasCook: hasCook)
        switch kind {
        case .cooking: return cookID
        case .eatOut: return hasCook ? cookID : authorID
        case .planned: return authorID
        }
    }

    static func speakerName(
        eatingOut: Bool, hasCook: Bool, cookName: String, authorName: String
    ) -> String {
        let kind = kind(eatingOut: eatingOut, hasCook: hasCook)
        switch kind {
        case .cooking: return cookName
        case .eatOut: return hasCook ? cookName : authorName
        case .planned: return authorName
        }
    }

    static func cooking(isYou: Bool, firstName: String) -> String {
        isYou ? "You're cooking" : "\(firstName) is cooking"
    }

    static func planned(isYou: Bool, firstName: String) -> String {
        isYou ? "You planned this night" : "\(firstName) planned this night"
    }

    static func eatOut(isYou: Bool, firstName: String) -> String {
        isYou ? "You: we're eating out" : "\(firstName): we're eating out"
    }

    static func line(kind: Kind, actor: Actor) -> String {
        switch kind {
        case .cooking: return cooking(isYou: actor.isYou, firstName: actor.firstName)
        case .planned: return planned(isYou: actor.isYou, firstName: actor.firstName)
        case .eatOut: return eatOut(isYou: actor.isYou, firstName: actor.firstName)
        }
    }

    static func whoLine(
        eatingOut: Bool,
        hasCook: Bool,
        cookIsYou: Bool,
        cookFirstName: String,
        plannerIsYou: Bool,
        plannerFirstName: String
    ) -> String {
        let kind = kind(eatingOut: eatingOut, hasCook: hasCook)
        let actor = actor(
            eatingOut: eatingOut,
            hasCook: hasCook,
            cookIsYou: cookIsYou,
            cookFirstName: cookFirstName,
            plannerIsYou: plannerIsYou,
            plannerFirstName: plannerFirstName
        )
        return line(kind: kind, actor: actor)
    }

    static func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    /// Same shape as `HouseholdMember.initials`, for a name with no row.
    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let joined = parts.compactMap { $0.first }.map(String.init).joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }

    static func member(id: String, in members: [HouseholdMember]) -> HouseholdMember? {
        guard !id.isEmpty else { return nil }
        return members.first {
            $0.identityKey == id
                || $0.userRecordName == id
                || ($0.participantID ?? "") == id
        }
    }
}

extension PlanRowVoice {
    /// Local night: cook when there is one, otherwise this phone's planner.
    /// An unstamped `authorID` is this device's own, the same rule
    /// `PlannedMeal.authorID` documents.
    @MainActor
    static func whoLine(for meal: PlannedMeal, members: [HouseholdMember]) -> String {
        facts(for: meal, members: members).line
    }

    @MainActor
    static func faceMember(for meal: PlannedMeal, members: [HouseholdMember]) -> HouseholdMember? {
        facts(for: meal, members: members).member
    }

    @MainActor
    private static func facts(
        for meal: PlannedMeal, members: [HouseholdMember]
    ) -> (line: String, member: HouseholdMember?) {
        let cook = meal.cook
        let planner = planner(for: meal, members: members)
        let eatingOut = isEatingOut(title: meal.title, hasRecipe: meal.recipe != nil)
        let line = whoLine(
            eatingOut: eatingOut,
            hasCook: cook != nil,
            cookIsYou: cook?.isMe ?? false,
            cookFirstName: cook?.firstName ?? "",
            plannerIsYou: planner.isYou,
            plannerFirstName: planner.firstName
        )
        let member: HouseholdMember?
        if eatingOut {
            member = cook ?? planner.member
        } else if let cook {
            member = cook
        } else {
            member = planner.member
        }
        return (line, member)
    }

    @MainActor
    private static func planner(
        for meal: PlannedMeal, members: [HouseholdMember]
    ) -> (isYou: Bool, firstName: String, member: HouseholdMember?) {
        let me = members.me
        let id = meal.authorID
        if id.isEmpty {
            return (true, me?.firstName ?? "", me)
        }
        if let found = member(id: id, in: members) {
            return (found.isMe, found.firstName, found)
        }
        if id == TableIdentity.cached {
            return (true, me?.firstName ?? "", me)
        }
        return (false, "", nil)
    }
}
