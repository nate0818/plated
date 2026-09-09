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
            let n = member.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return n.isEmpty || n == "someone" ? nil : n
        })
        return all().filter { !$0.settled && !taken.contains($0.name.lowercased()) }
    }

    static func markSettled(name: String) {
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
    static func rememberedName(forPhone phone: String?, email: String?) -> String? {
        let rows = all().filter { !$0.settled }
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
        // Sole unsettled invitation is the only person this restore could be.
        if rows.count == 1 { return rows[0].name }
        return nil
    }

    private static func save(_ rows: [Entry]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        defaults.set(data, forKey: key)
    }
}
