import SwiftUI

/// A night somebody else planned, drawn beside this phone's own.
///
/// A remote night is a `PlanLedger.Entry`, never a `PlannedMeal`, and the
/// planner draws it beside this phone's own nights (docs/plan-share.md,
/// "Drawing a remote night"). The geometry is `WeekView.plannedRow`'s,
/// because peers look like peers: canvas ground at `Radius.row`, the 0.5pt
/// hairline underline, the 40pt date column, 60pt artwork at `Radius.small`,
/// minHeight 76.
///
/// It is editable now, through the same door the local row uses: a tap into
/// the day, and on the day page a tap into `PlanNightSheet`, which changes
/// the night by writing the household zone record. What it still may never
/// carry is a drag lift or a Move: moving a night swaps two nights' dates,
/// and the night on the other date is very often this phone's own
/// `PlannedMeal`, so one gesture would be two writes in two authorities.
/// Nor a Cooked toggle, nor a Let's cook it cannot honour.
///
/// `onOpen` nil means the row is a fact, not a door: no tap, no button
/// trait, no hint. A night that is going is drawn that way: see `isGoing`.
struct RemotePlanRow: View {
    let entry: PlanLedger.Entry
    let date: Date
    var members: [HouseholdMember] = []
    var onOpen: (() -> Void)? = nil
    /// What the tap opens, said out loud. The week and the month open the
    /// day; the day page opens the night itself, where it can be changed.
    var openHint: String = "Opens the day"
    /// Which list this row is standing in, which decides its geometry.
    ///
    /// DESIGN.md: one row, one geometry, and peers look like peers. In the
    /// week and the month a remote night stands beside `plannedRow`, so it
    /// wears the week list's clothes: a date column, because the list spans
    /// days, and a hairline underline. On the day page it stands beside
    /// `mealCard`, which is a bordered card on a page whose title is
    /// already the date, so it wears that instead. Drawn in the week's
    /// clothes there, it read as a different kind of thing from the meal
    /// directly above it, and repeated a date the masthead had already said.
    enum Place { case week, day }
    var place: Place = .week

    private var ledger: PlanLedger { PlanLedger.shared }
    private var today: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        let cookLine = ledger.cookLine(for: entry)
        HStack(spacing: 10) {
            if place == .week { PlanDateColumn(date: date) }

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
        .padding(.leading, place == .week ? 8 : 14)
        .padding(.trailing, 14)
        .frame(minHeight: 76)
        .background(Color.canvas, in: Radius.shape(Radius.row))
        .overlay {
            // The stroke is the geometry, not decoration: the day page's
            // meal above this one is a bordered card, and a row that
            // answered it with an underline read as a different species.
            switch place {
            case .week:
                VStack { Spacer(); Rectangle().fill(Color.hairline).frame(height: 0.5) }
            case .day:
                Radius.shape(Radius.row).strokeBorder(Color.navHairline, lineWidth: 1.5)
            }
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
        .accessibilityHint(onOpen == nil ? "" : openHint)
    }

    /// "Planned by Nate", joined to the night's own tag line the way the
    /// local row joins its parts. A change this phone has made but not sent
    /// says so here: the row already shows the new dish, and the sentence is
    /// what keeps that from being a claim that the household has it.
    ///
    /// A night that is going replaces the author with what is happening to
    /// it, in the same quiet caption. The row is still standing and its dish
    /// is still drawn, so without this a delete that has not left the phone
    /// looks exactly like a night nobody touched. Its own tag line goes too:
    /// "Picked for you" under a night coming off the plan is a sentence
    /// about a dinner that is no longer the point, and three clauses
    /// truncate at the larger type sizes. `pendingLine` is the ledger's, so
    /// the caption and the hero cannot drift into two vocabularies.
    ///
    /// Static so the sentence can be read in a test, and so the sheet's own
    /// card says these words rather than keeping a second copy of them: two
    /// hand-kept captions for one night is how two screens drift, which is
    /// why `OptionRow` is in Theme.swift at all.
    static func caption(for entry: PlanLedger.Entry) -> String {
        var parts = entry.isGoing ? ["Coming off the plan"] : ["Planned by \(entry.authorFirstName)"]
        if !entry.isGoing, !entry.tagline.isEmpty { parts.append(entry.tagline) }
        if let pending = entry.pendingLine { parts.append(pending) }
        return parts.joined(separator: " · ")
    }

    private var caption: String { Self.caption(for: entry) }

    /// "Thursday, Tacos, Riley is cooking, planned by Nate".
    static func spokenLabel(entry: PlanLedger.Entry, day: String, cookLine: String?) -> String {
        var parts = [day, entry.title]
        if let cookLine { parts.append(cookLine) }
        parts.append("planned by \(entry.authorFirstName)")
        if let pending = entry.pendingSpoken { parts.append(pending) }
        return parts.joined(separator: ", ")
    }

    private func spokenLabel(cookLine: String?) -> String {
        Self.spokenLabel(
            entry: entry,
            day: today ? "Tonight" : date.formatted(.dateTime.weekday(.wide)),
            cookLine: cookLine
        )
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
