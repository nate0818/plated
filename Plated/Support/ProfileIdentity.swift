import Foundation

/// Names are labels, not account keys. Legacy content may use a name only
/// when exactly one posting-capable seat can answer for it.
enum ProfileIdentity {
    static func member(authorID: String, name: String, in members: [HouseholdMember]) -> HouseholdMember? {
        let people = members.filter { !$0.isDeleted && $0.seat.canPost }
        if !authorID.isEmpty {
            if let member = PlanRowVoice.member(id: authorID, in: people) { return member }
            return authorID == TableIdentity.cached ? people.first(where: \.isMe) : nil
        }
        let exact = people.filter { $0.name == name }
        if exact.count == 1 { return exact[0] }
        guard exact.isEmpty else { return nil }
        let first = PlanRowVoice.firstName(name)
        guard !HouseholdIdentity.isUnnamed(first) else { return nil }
        let matches = people.filter { $0.firstName == first }
        return matches.count == 1 ? matches[0] : nil
    }

    static func matches(authorID: String, authorName: String, member: HouseholdMember?,
                        profileID: String = "", profileName: String, roster: [HouseholdMember]) -> Bool {
        let identity = member?.identityKey ?? (member?.isMe == true ? TableIdentity.cached : profileID)
        if !authorID.isEmpty {
            guard !identity.isEmpty else { return false }
            return authorID == identity || member?.participantID == authorID
        }
        if let member {
            return self.member(authorID: "", name: authorName, in: roster)?.persistentModelID == member.persistentModelID
        }
        return authorName == profileName
    }

    /// Unstamped legacy recipes belong to this account. A same-name household
    /// member must never inherit another account's recipes or private collection.
    static func owns(recipe: Recipe, member: HouseholdMember?, profileID: String,
                     profileName: String, roster: [HouseholdMember], isMe: Bool) -> Bool {
        guard !recipe.isDeleted, isMe || recipe.visibility != "private" else { return false }
        if recipe.authorID.isEmpty { return isMe }
        return matches(authorID: recipe.authorID, authorName: "", member: member,
                       profileID: profileID, profileName: profileName, roster: roster)
    }

}
