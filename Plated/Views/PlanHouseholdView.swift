import SwiftUI
import SwiftData

struct PlanHouseholdView: View {
    let members: [HouseholdMember]
    let meals: [PlannedMeal]
    var openPerson: (HouseholdMember) -> Void
    var openHousehold: () -> Void
    @Query(sort: \TablePost.createdAt, order: .reverse) private var posts: [TablePost]
    @Environment(\.dynamicTypeSize) private var typeSize

    private var roster: [HouseholdMember] { members.readable.occupying }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                Text("At home").plType(.heading).foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button("Household", action: openHousehold).plType(.footnote, .semibold)
                    .foregroundStyle(Color.accentText).plTapTarget()
                    .accessibilityLabel("Manage household")
            }
            Text("Recorded activity · last 7 days").plType(.caption).foregroundStyle(Color.inkSecondary)
            ForEach(roster, id: \.persistentModelID) { member in
                let display = Seats.resolvedDisplay(for: member, among: roster)
                let activity = MemberDinnerActivity(member: member, roster: roster, meals: meals,
                    remote: PlanLedger.shared.all,
                    posts: posts.filter { !ContentSafety.shared.isBlocked(authorID: $0.authorID, authorName: $0.authorName) })
                let detail = member.seat == .invited ? "Invitation pending" : activity.latest.map { "\($0.line) · \(Stamp.day($0.date))" } ?? activity.summary
                Button { openPerson(member) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        AvatarCircle(initials: member.initials, tone: member.tone, size: 36, photo: display.photo)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.isMe ? "You" : display.name).plType(.body, .semibold).foregroundStyle(Color.ink)
                            Text(detail).plType(.caption).foregroundStyle(Color.inkSecondary)
                        }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)

                    }.frame(minHeight: 44).padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.pressable)
                    .accessibilityLabel("\(member.isMe ? "You" : display.name), \(detail)")
                    .accessibilityHint("Opens profile")
                    .accessibilityIdentifier("plan-household-\(member.shareRecordName)")
            }
            if roster.isEmpty {
                Text("Add the people you plan and cook with.").plType(.footnote).foregroundStyle(Color.inkSecondary)
            }
        }
    }
}
