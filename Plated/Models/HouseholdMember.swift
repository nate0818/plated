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
        /// They were joined and walked out. Written by the leaver's own
        /// phone before it deletes the zone, so the host hears it instead of
        /// keeping a row that cooks Thursday for somebody who is gone. Seats
        /// only move forward, and this is the last stop.
        case left
    }

    var name: String = ""
    var dietaryNotes: String = ""
    /// Ingredient names to flag on sight — allergies, dislikes, hard no's.
    var avoidedIngredients: [String] = []
    /// Hex string (no leading `#`) used to tint this member across the app.
    /// Tomato — first in `PersonTone.rotation` — so a new seat maps to a
    /// known tone pair rather than the unmapped terracotta that used to
    /// fall through to neutral.
    var colorHex: String = "FF5A3C"
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
    /// When they left, if they did. Never cleared once set.
    var leftAt: Date?

    // MARK: Who this is, across Apple IDs

    /// The CloudKit user record name of the person this seat is, the same
    /// string `TableIdentity.cached` answers on their own phone. Set once,
    /// never replaced: a seat that carries an identity belongs to that
    /// person, and a second claimant gets a fresh seat instead. Nil until
    /// somebody has taken the seat.
    var userRecordName: String?
    /// A line about themselves, shown on their profile. Self-owned: only the
    /// phone whose identity this is may write it (see docs/household.md).
    var bio: String = ""
    /// The identity that created this row, for the one question leaving
    /// asks: what did I bring, and what was theirs. "" on rows that predate
    /// the field, which count as this device's own.
    var authorID: String = ""

    // MARK: How this row travels

    /// The CloudKit record name this seat is written as in the household
    /// zone, minted at birth so two devices of one Apple ID can never name
    /// one row twice. The merge keys on it. "" only on rows that predate the
    /// field, which the single minter names at the moment the household is
    /// first shared (docs/household.md §2).
    var shareRecordName: String = ""
    /// `modifiedAt` of the version last exchanged with the zone. Nil means
    /// never synced. Compared as a version, never as a clock.
    var shareModifiedAt: Date?
    /// Hash of the wire fields as last exchanged. The save observer enqueues
    /// a push only when the live fingerprint differs, which is what keeps
    /// bookkeeping saves from enqueueing themselves forever.
    var shareFingerprint: String = ""

    @Relationship(deleteRule: .nullify, inverse: \PlannedMeal.cook)
    var assignedMeals: [PlannedMeal]? = []

    init(
        name: String = "",
        dietaryNotes: String = "",
        avoidedIngredients: [String] = [],
        colorHex: String = "FF5A3C",
        isPrimaryCook: Bool = false,
        role: String = "member",
        roleLine: String = "",
        cookWeekdays: [Int] = [],
        seat: Seat = .notOnPlated,
        phoneE164: String? = nil,
        inviteEmail: String? = nil,
        invitedAt: Date? = nil,
        shareRecordName: String? = nil
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
        // Identity at birth, like a post. A row named after the fact is a row
        // two devices can name differently.
        self.shareRecordName = shareRecordName ?? "seat-\(UUID().uuidString)"
    }

    var seat: Seat {
        get { Seat(rawValue: seatRaw) ?? .notOnPlated }
        set { seatRaw = newValue.rawValue }
    }

    /// Head of table, and nothing else. This gates what a host may do to
    /// other seats (Remove, Change role) and who carries the reserved
    /// tomato. It does NOT mean "the person holding the phone": on a
    /// member's phone the head is somebody else. That is `isMe`.
    var isOwner: Bool { role == "owner" }

    /// The person holding this phone. Identity, never role: on a member's
    /// phone the owner row is the host, and every screen that once asked
    /// `isOwner` to find "you" was about to call the host "you".
    var isMe: Bool {
        if let userRecordName, !userRecordName.isEmpty {
            return userRecordName == TableIdentity.cached
        }
        // No identity on the row yet. In a household that has never been
        // shared there is exactly one head and it is the person holding
        // the phone: every household that predates identity, and every
        // simulator, which has no iCloud to confirm one. On a member's
        // phone the head is somebody else, and the seat this phone claimed
        // is remembered in the app group, so neither fallback can name the
        // host "you" there.
        guard isOwner, !Self.isMemberElsewhere else { return false }
        return Self.claimedSeatName == nil
    }

    /// The role as a person would say it.
    var roleTitle: String {
        switch role {
        case "owner": return "Head of table"
        case "partner": return "Partner"
        case "kid": return "Kid"
        default: return "Member"
        }
    }

    // MARK: App-group facts the model needs without owning them
    //
    // Written by HouseholdShare (the wire) and read here so `me` can answer
    // synchronously in a SwiftUI body. Keys, not a dependency: the model must
    // stay buildable in the test target's CloudKit-free container.

    enum Keys {
        /// "solo", "hosting" or "member". See HouseholdShare.Membership.
        static let membershipKind = "plated.household.membership.kind"
        /// The `shareRecordName` of the seat this phone claimed at join.
        static let mySeat = "plated.household.mySeat"
    }

    private static var groupDefaults: UserDefaults {
        UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
    }

    static var claimedSeatName: String? {
        groupDefaults.string(forKey: Keys.mySeat)
    }

    static var isMemberElsewhere: Bool {
        groupDefaults.string(forKey: Keys.membershipKind) == "member"
    }

    // MARK: What a row is allowed to say

    /// The line under the name. State first, because state is the thing
    /// every row was quietly lying about. None of these describes the other
    /// person's behaviour — "Waiting on them" was a claim about somebody
    /// who had never been told anything existed. These say only what we did
    /// and what is true here.
    ///
    /// A joined seat genuinely shares the plan, the list and the cookbook
    /// now (docs/household.md), so the sentence says what they can do, by
    /// role: a partner cooks, a kid or member sees. The reader's own row is
    /// addressed as "You", never with a sentence written for somebody else.
    var subtitle: String {
        if isMe { return "You · \(roleTitle)" }
        switch seat {
        case .head: return "Head of table"
        case .joined:
            return role == "partner" || role == "owner"
                ? "Plans and cooks with you" : "Sees the plan with you"
        case .invited:
            guard let invitedAt else { return "Invited a while back" }
            return "Invited \(Self.when(invitedAt))"
        case .notOnPlated: return "You cook for them"
        case .left: return "Left"
        }
    }

    /// Colour is earned by being here. An invitation is the one unresolved
    /// thing, so an invited row is the one row that stays grey — their
    /// colour arrives when they do. A kid keeps full colour, because
    /// nothing about a kid is pending.
    var showsColor: Bool { seat != .invited && seat != .left }

    /// Eligible to be handed a night by the rotation. Kids and guests keep
    /// their seat without keeping the pan; an invitation is not a household
    /// member yet, whatever the row looks like, and somebody who left has
    /// no pan to keep.
    var cooks: Bool {
        guard seat != .invited, seat != .left else { return false }
        return role == "owner" || role == "partner"
    }

    /// Somewhere a message can actually go. Nil means no Message button —
    /// which is most rows, and is why the button used to be a lie. Never
    /// for the reader's own row: a member's phone must not offer them a
    /// Message button to themselves.
    var messageURL: URL? {
        guard seat != .head, !isMe else { return nil }
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

    /// The day the invitation went, for the seat record's wire form and the
    /// household digest's relative dates.
    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

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


extension Array where Element == HouseholdMember {
    /// The person holding this phone.
    ///
    /// Identity first. While no row carries one and this phone is not a
    /// member of somebody else's household, the head is the reader: that is
    /// every household that predates identity, and on the host's phone the
    /// two are the same person. On a member's phone the claimed seat is
    /// remembered in the app group, so a placeholder identity on an offline
    /// launch cannot make the host "you"; and if even that is missing the
    /// answer is nobody, which is honest, rather than the host, which is a
    /// lie every screen would repeat.
    var me: HouseholdMember? {
        if let mine = first(where: \.isMe) { return mine }
        if let seat = HouseholdMember.claimedSeatName, !seat.isEmpty,
           let claimed = first(where: { $0.shareRecordName == seat }) {
            return claimed
        }
        guard !HouseholdMember.isMemberElsewhere else { return nil }
        return first(where: \.isOwner)
    }

    /// The people the host actually keeps this household with, by name.
    ///
    /// A joined seat is somebody who arrived and a by-name seat is a full
    /// seat, so both belong in the host's own sentence about the household
    /// (docs/household.md §10). An invited seat is a message that went out
    /// and nothing that came back: naming it here would tell the host they
    /// host the household with a person who has never taken the seat, which
    /// is the roster's "Invited Tuesday" to say and not this line's. A seat
    /// that left is not one anybody is hosting with.
    var hostedNames: [String] {
        filter { !$0.isMe && ($0.seat == .joined || $0.seat == .notOnPlated) }.map(\.name)
    }

    /// Who a night can be handed to. A seat that left is still on a
    /// member's roster until the host's delete arrives (§8), and offering
    /// it here is how "Their nights are open again." ends up over a week
    /// that still says Riley cooks Thursday.
    var assignableCooks: [HouseholdMember] {
        filter { $0.seat != .left }
    }
}
