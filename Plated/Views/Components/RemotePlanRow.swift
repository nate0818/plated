import SwiftUI

/// A night somebody else planned, drawn beside this phone's own.
///
/// A remote night is a `PlanLedger.Entry`, never a `PlannedMeal`, and the
/// planner draws it as a read-only overlay (docs/plan-share.md, "Drawing a
/// remote night"). The geometry is `WeekView.plannedRow`'s, because peers
/// look like peers: canvas ground at `Radius.row`, the 0.5pt hairline
/// underline, the 40pt date column, 60pt artwork at `Radius.small`, minHeight
/// 76. What it may never carry: a swipe tray, a drag lift, an ellipsis, Edit,
/// Move, Remove, Cooked, or a Let's cook it cannot honour. The zone permits
/// the write, but the origin phone would have to merge it back into its own
/// `PlannedMeal`, and a control that does nothing is the honesty rule broken.
///
/// `onOpen` nil means the row is a fact, not a door: no tap, no button
/// trait, no hint. The day page lists it that way, since it is already the
/// day.
struct RemotePlanRow: View {
    let entry: PlanLedger.Entry
    let date: Date
    var members: [HouseholdMember] = []
    var onOpen: (() -> Void)? = nil

    private var ledger: PlanLedger { PlanLedger.shared }
    private var today: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        let cookLine = ledger.cookLine(for: entry)
        HStack(spacing: 10) {
            PlanDateColumn(date: date)

            RecipeArtwork(data: ledger.photo(for: entry.recordName), title: entry.title, ratio: 1, radius: Radius.small)
                .frame(width: 60)
                .overlay(alignment: .bottomTrailing) {
                    // The cook belongs to the dish, the same corner the local
                    // row uses. Not when the cook is me: "You're cooking" is
                    // already on the line beside it, and my own face on my
                    // own dish is decoration, the rule plannedRow follows.
                    if cookLine != nil, !ledger.isMine(cook: entry) {
                        RemoteCookFace(entry: entry, members: members, size: 22)
                            // A face on a photograph needs its own edge or
                            // it reads as part of the dish.
                            .overlay { Circle().strokeBorder(Color.cardFill, lineWidth: 2) }
                            .offset(x: 3, y: 3)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .plType(.callout, .semibold)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                if let cookLine {
                    Text(cookLine)
                        .plType(.caption, .semibold)
                        .foregroundStyle(today ? Color.ink : Color.inkSecondary)
                        .lineLimit(1)
                }
                // `.plType(.micro)` and not `MicroLabel`, which uppercases:
                // this is a sentence about a person, not an eyebrow.
                Text(caption)
                    .plType(.micro)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 12)
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(minHeight: 76)
        .background(Color.canvas, in: Radius.shape(Radius.row))
        .overlay {
            VStack { Spacer(); Rectangle().fill(Color.hairline).frame(height: 0.5) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let onOpen else { return }
            Haptic.tap()
            onOpen()
        }
        // A gesture announces nothing on its own; the combined row reads as
        // one sentence and, when it opens the day, says it is a button.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel(cookLine: cookLine))
        .accessibilityAddTraits(onOpen == nil ? [] : .isButton)
        .accessibilityHint(onOpen == nil ? "" : "Opens the day")
    }

    /// "Planned by Nate", joined to the night's own tag line the way the
    /// local row joins its parts.
    private var caption: String {
        let planned = "Planned by \(entry.authorFirstName)"
        return entry.tagline.isEmpty ? planned : "\(planned) · \(entry.tagline)"
    }

    /// "Thursday, Tacos, Riley is cooking, planned by Nate".
    private func spokenLabel(cookLine: String?) -> String {
        var parts = [today ? "Tonight" : date.formatted(.dateTime.weekday(.wide)), entry.title]
        if let cookLine { parts.append(cookLine) }
        parts.append("planned by \(entry.authorFirstName)")
        return parts.joined(separator: ", ")
    }
}

/// The cook's face for a remote night, by identity and never by name.
///
/// The `HouseholdMember` whose `participantID` is the entry's `cookID`
/// when this roster has one, otherwise a neutral monogram from the name.
/// Asymmetry, stated in the spec: a guest's roster has no row for the host,
/// so the host's face is a monogram on a member's phone until the guest
/// side learns identities from the share.
struct RemoteCookFace: View {
    let entry: PlanLedger.Entry
    var members: [HouseholdMember] = []
    var size: CGFloat = 26

    var body: some View {
        if let member = Self.member(for: entry, in: members) {
            AvatarCircle(member: member, size: size)
        } else {
            AvatarCircle(initials: Self.initials(entry.cookName), tone: .neutralPair, size: size)
        }
    }

    static func member(for entry: PlanLedger.Entry, in members: [HouseholdMember]) -> HouseholdMember? {
        guard !entry.cookID.isEmpty else { return nil }
        return members.first { $0.participantID == entry.cookID }
    }

    /// Same shape as `HouseholdMember.initials`, for a name with no row.
    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let joined = parts.compactMap { $0.first }.map(String.init).joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }
}

/// The week list's date column: the weekday over the day number, today's
/// numeral on the tomato disc. One view for the local rows and the remote
/// row, so the two can never drift a point apart. `WeekView.dateColumn`
/// draws this; it is here because the remote row needs it too.
struct PlanDateColumn: View {
    let date: Date

    var body: some View {
        let today = Calendar.current.isDateInToday(date)
        VStack(spacing: 4) {
            Text(date.formattedWeekday().uppercased())
                .plType(.micro, .semibold).foregroundStyle(Color.inkSecondary)
            Text(date.formattedDayNumber())
                .plType(today ? .callout : .heading, .semibold, family: .display).monospacedDigit()
                .foregroundStyle(today ? Color.onTomato : Color.ink)
                .frame(width: 32, height: 32)
                .background(today ? Color.tomato : Color.clear, in: Circle())
        }
        .plChrome()
        .frame(width: 40)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day()) + (today ? ", today" : ""))
    }
}
