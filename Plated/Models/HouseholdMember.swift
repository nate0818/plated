import Foundation
import SwiftData

/// A person the household cooks for.
///
/// One row per human, in exactly one `Seat` at a time. The seat is the only
/// thing allowed to say how real a person is, and it is never asserted — it
/// is set from something that verifiably happened: a message the system
/// composer reported as sent, a share participant that actually accepted.
/// Everything downstream is gated on it: whether the rota may hand them a
/// night, whether a push may say their name, whether a Message button
/// appears, whether their colour has been earned.
///
/// Before this, a name typed four seconds ago and a person who had accepted
/// a share were the same object wearing the same clothes, so no screen
/// could tell the truth even when it wanted to.
@Model
final class HouseholdMember {

    /// Where this person actually stands. Exactly one, always.
    enum Seat: String, Codable, CaseIterable {
        /// You. The iCloud account this table belongs to.
        case head
        /// They accepted the share. The table is on their phone too.
        case joined
        /// A message carrying a working link genuinely sent, and they are a
        /// pending participant on the share. Nothing has come back yet.
        case invited
        /// No app, no invitation, none possible or wanted — a kid, a
        /// grandparent, a flatmate who doesn't want another icon. A full
        /// seat, not a lesser one: this is who most households cook for.
        case notOnPlated
    }

    var name: String = ""
    var dietaryNotes: String = ""
    /// Ingredient names to flag on sight — allergies, dislikes, hard no's.
    var avoidedIngredients: [String] = []
    /// Hex string (no leading `#`) used to tint this member across the app.
    var colorHex: String = "C86629"
    var isPrimaryCook: Bool = false
    /// "owner" (head of table), "partner", "kid", or "member".
    var role: String = "member"
    /// The line under the name — "Partner · plans & cooks".
    var roleLine: String = ""
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday) this person cooks.
    var cookWeekdays: [Int] = []
    /// This person's face. Downsized JPEG, same treatment as a recipe photo.
    ///
    /// Optional because it always can be: Sign in with Apple does not hand
    /// over the Apple ID picture and never has, so there is no path that
    /// guarantees one. What there IS is a good path, and the monogram is the
    /// floor rather than the default. See `ProfilePhoto`.
    @Attribute(.externalStorage) var photoData: Data?
    var createdAt: Date = Date.now

    // MARK: Where they stand

    /// Stored raw so SwiftData and the CloudKit mirror see a plain String.
    /// Rows that predate this land on `notOnPlated`, which is the truth
    /// about every one of them: they were typed, and nobody was contacted.
    var seatRaw: String = Seat.notOnPlated.rawValue

    /// The number the invitation actually went to, E.164. This is the join
    /// key that lets the share's participants and this table finally be one
    /// list: a *pending* CKShare participant has no user record to match
    /// on, but it always carries back the lookup info it was added with.
    var phoneE164: String?
    /// The address used instead, when the contact had no mobile number.
    var inviteEmail: String?
    /// When a message carrying a working link genuinely sent. Nil on rows
    /// carried over from the old pending-seats string, where a message did
    /// go but nothing recorded when — the subtitle says exactly that rather
    /// than inventing a date.
    var invitedAt: Date?
    /// First time they showed as accepted on the share.
    var joinedAt: Date?
    /// CKShare participant record name, once they accept. What removal
    /// revokes on, so removing somebody stops being cosmetic.
    var participantID: String?

    @Relationship(deleteRule: .nullify, inverse: \PlannedMeal.cook)
    var assignedMeals: [PlannedMeal]? = []

    init(
        name: String = "",
        dietaryNotes: String = "",
        avoidedIngredients: [String] = [],
        colorHex: String = "C86629",
        isPrimaryCook: Bool = false,
        role: String = "member",
        roleLine: String = "",
        cookWeekdays: [Int] = [],
        seat: Seat = .notOnPlated,
        phoneE164: String? = nil,
        inviteEmail: String? = nil,
        invitedAt: Date? = nil
    ) {
        self.name = name
        self.dietaryNotes = dietaryNotes
        self.avoidedIngredients = avoidedIngredients
        self.colorHex = colorHex
        self.isPrimaryCook = isPrimaryCook
        self.role = role
        self.roleLine = roleLine
        self.cookWeekdays = cookWeekdays
        self.seatRaw = seat.rawValue
        self.phoneE164 = phoneE164
        self.inviteEmail = inviteEmail
        self.invitedAt = invitedAt
        self.createdAt = .now
    }

    var seat: Seat {
        get { Seat(rawValue: seatRaw) ?? .notOnPlated }
        set { seatRaw = newValue.rawValue }
    }

    var isOwner: Bool { role == "owner" }

    // MARK: What a row is allowed to say

    /// The line under the name. State first, because state is the thing
    /// every row was quietly lying about. None of these describes the other
    /// person's behaviour — "Waiting on them" was a claim about somebody
    /// who had never been told anything existed. These say only what we did
    /// and what is true here.
    var subtitle: String {
        switch seat {
        case .head: return "Head of table"
        case .joined: return "Sees this too"
        case .invited:
            guard let invitedAt else { return "Invited a while back" }
            return "Invited \(Self.when(invitedAt))"
        case .notOnPlated: return "You cook for them"
        }
    }

    /// Colour is earned by being here. An invitation is the one unresolved
    /// thing, so an invited row is the one row that stays grey — their
    /// colour arrives when they do. A kid keeps full colour, because
    /// nothing about a kid is pending.
    var showsColor: Bool { seat != .invited }

    /// Eligible to be handed a night by the rotation. Kids and guests keep
    /// their seat without keeping the pan; an invitation is not a household
    /// member yet, whatever the row looks like.
    var cooks: Bool {
        guard seat != .invited else { return false }
        return role == "owner" || role == "partner"
    }

    /// Somewhere a message can actually go. Nil means no Message button —
    /// which is most rows, and is why the button used to be a lie.
    var messageURL: URL? {
        guard seat != .head else { return nil }
        if let phoneE164, !phoneE164.isEmpty { return URL(string: "sms:\(phoneE164)") }
        if let inviteEmail, !inviteEmail.isEmpty { return URL(string: "mailto:\(inviteEmail)") }
        return nil
    }

    /// An invitation we can send again, because the link and the recipient
    /// both still exist.
    var canResend: Bool {
        seat == .invited && (phoneE164?.isEmpty == false || inviteEmail?.isEmpty == false)
    }

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }

    var firstInitial: String { name.first.map(String.init)?.uppercased() ?? "?" }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    /// "today", "yesterday", "Tuesday", "last week", "3 weeks ago",
    /// "in March" — an invitation ages on its own so nobody has to wonder
    /// whether it is stale.
    static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        let days = calendar.dateComponents([.day], from: date, to: .now).day ?? 0
        if days < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }
        if days < 14 { return "last week" }
        if days < 60 { return "\(days / 7) weeks ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return "in \(formatter.string(from: date))"
    }
}
