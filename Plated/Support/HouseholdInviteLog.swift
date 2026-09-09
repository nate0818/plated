import Foundation

/// Household invitations this phone actually sent.
///
/// Survives deleting the Invited roster row — which is what let Alessandra
/// disappear from People while we still knew who had been invited. Restore
/// reads this book for a real name when CloudKit only hands back an empty
/// identity, and Home can offer "Invite again" without asking Nate to
/// remember the contact.
@MainActor
enum HouseholdInviteLog {
    struct Entry: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var phone: String?
        var email: String?
        var seat: String?
        var sentAt: Date

        /// True once a joined seat on this phone carries this person.
        var settled: Bool
    }

    private static let key = "plated.household.inviteLog"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
    }

    static func all() -> [Entry] {
        guard let data = defaults.data(forKey: key),
              let rows = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return rows.sorted { $0.sentAt > $1.sentAt }
    }

    static func record(name: String, phone: String?, email: String?, seat: String?) {
        var rows = all()
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        // Same seat or same phone → refresh rather than duplicate.
        rows.removeAll {
            ($0.seat != nil && $0.seat == seat)
                || ($0.phone != nil && !$0.phone!.isEmpty && $0.phone == phone)
                || ($0.name.caseInsensitiveCompare(clean) == .orderedSame && $0.settled == false)
        }
        rows.append(Entry(
            id: UUID().uuidString,
            name: clean,
            phone: phone,
            email: email,
            seat: seat,
            sentAt: .now,
            settled: false
        ))
        save(rows)
        print("PLATED HOUSEHOLD: logged invitation for \(clean)")
    }

    /// Names from invitations that are not yet represented by a joined seat.
    static func unsettled(against members: [HouseholdMember]) -> [Entry] {
        let taken = Set(members.compactMap { member -> String? in
            guard member.seat == .joined || member.seat == .head else { return nil }
            let n = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return HouseholdIdentity.isUnnamed(n) ? nil : n.lowercased()
        })
        return all().filter { !$0.settled && !taken.contains($0.name.lowercased()) }
    }

    static func markSettled(name: String) {
        if HouseholdIdentity.isUnnamed(name) { return }
        var rows = all()
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        var changed = false
        for i in rows.indices where rows[i].name.lowercased() == key {
            if !rows[i].settled { rows[i].settled = true; changed = true }
        }
        if changed { save(rows) }
    }

    /// Best remembered name for a restored share participant with no CloudKit name.
    ///
    /// Settled entries still count: that flag means "we already have a
    /// joined seat for this person", not "forget who they are". TF26 left
    /// Alessandra as "New member" after the log was marked settled and the
    /// drawn seat had no name.
    ///
    /// `excluding` is the host / owner display names. A sole-entry or
    /// unique-name fallback that can only answer with the host is how
    /// TF27 printed "Nate and Nate". Phone / email / seat hits are
    /// refused for the same reason: the log must never name a joiner
    /// after the person who sent the invite.
    static func rememberedName(
        forPhone phone: String?,
        email: String?,
        seat: String? = nil,
        excluding hostNames: [String] = []
    ) -> String? {
        let rows = all().filter {
            !HouseholdIdentity.isUnnamed($0.name)
                && !HouseholdIdentity.isHostClone($0.name, hosts: hostNames)
        }
        func usable(_ name: String) -> String? {
            HouseholdIdentity.isHostClone(name, hosts: hostNames) ? nil : name
        }
        if let seat, !seat.isEmpty,
           let hit = rows.first(where: { $0.seat == seat }) {
            return usable(hit.name)
        }
        let unsettled = rows.filter { !$0.settled }
        if let name = match(phone: phone, email: email, in: unsettled) { return usable(name) }
        if unsettled.count == 1 { return usable(unsettled[0].name) }
        if let name = match(phone: phone, email: email, in: rows) { return usable(name) }
        let unique = Set(rows.map { $0.name.lowercased() })
        if unique.count == 1 { return usable(rows[0].name) }
        return nil
    }

    private static func match(phone: String?, email: String?, in rows: [Entry]) -> String? {
        if let phone, !phone.isEmpty {
            let want = Directory.normalize(phone) ?? phone
            if let hit = rows.first(where: {
                guard let have = $0.phone, !have.isEmpty else { return false }
                return have == phone || have == want || (Directory.normalize(have) ?? have) == want
            }) {
                return hit.name
            }
        }
        if let email, !email.isEmpty {
            let want = email.lowercased()
            if let hit = rows.first(where: { ($0.email ?? "").lowercased() == want }) {
                return hit.name
            }
        }
        return nil
    }

    /// Test hook. The log lives in the app group and otherwise leaks
    /// across in-memory store tests in one process.
    static func reset() {
        defaults.removeObject(forKey: key)
    }

    private static func save(_ rows: [Entry]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        defaults.set(data, forKey: key)
    }
}
