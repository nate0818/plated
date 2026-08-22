import SwiftUI
import SwiftData

/// The host's own card — opened from the avatar in the plan header. Who you
/// are at the table, the numbers you've earned, and the room's light switch.
struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query(filter: #Predicate<TablePost> { !$0.isDiscover }) private var posts: [TablePost]
    @Query private var recipes: [Recipe]

    @AppStorage("userBio") private var bio = ""
    @AppStorage("afterDark") private var afterDark = false
    @AppStorage("showCalendarEvents") private var showCalendarEvents = false
    @AppStorage("userFamilyName") private var userFamilyName = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    AvatarCircle(initials: owner?.firstInitial ?? "?", tone: .neutralPair, size: 84)
                    VStack(spacing: 2) {
                        Text(displayName)
                            .font(.gabarito(24, .extraBold))
                            .tracking(-0.4)
                            .foregroundStyle(Color.ink)
                        MicroLabel("Host · Head of table")
                    }
                    Text("Your table sees your initials for now — profile photos ride in with Plated's network.")
                        .font(.jakarta(11, .medium))
                        .foregroundStyle(Color.inkFaint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 26)

                VStack(alignment: .leading, spacing: 8) {
                    MicroLabel("Bio")
                    TextField("What kind of cook are you?", text: $bio, axis: .vertical)
                        .font(.jakarta(14, .medium))
                        .lineLimit(2...4)
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
                }

                HStack(spacing: 8) {
                    statCard("Dishes", "\(recipes.count)")
                    statCard("Posts", "\(myPosts.count)")
                    statCard("Kisses", "\(kissCount)", accent: kissCount > 0)
                    statCard("Saves", "\(savesReceived)")
                }

                VStack(alignment: .leading, spacing: 10) {
                    MicroLabel("The room")

                    toggleRow(
                        icon: afterDark ? "moon.stars.fill" : "moon",
                        title: "After Dark",
                        caption: "The warm room. Photos glow, chrome sleeps.",
                        isOn: $afterDark.animation(.plSettle)
                    ) { Haptic.plate() }

                    toggleRow(
                        icon: "calendar",
                        title: "Calendar on the plan",
                        caption: "Show your Apple Calendar events next to each night.",
                        isOn: $showCalendarEvents
                    ) {
                        if showCalendarEvents {
                            Task {
                                let granted = await DayEventsProvider.shared.requestAccess()
                                if !granted { showCalendarEvents = false }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    private var owner: HouseholdMember? { members.first(where: \.isOwner) }

    private var displayName: String {
        guard let owner else { return "You" }
        return userFamilyName.isEmpty ? owner.name : "\(owner.name) \(userFamilyName)"
    }

    private var myPosts: [TablePost] {
        guard let first = owner?.name else { return [] }
        return posts.filter { $0.authorName.hasPrefix(first) }
    }

    private var kissCount: Int { myPosts.filter(\.hasChefsKiss).count }

    private var savesReceived: Int {
        guard let owner else { return 0 }
        return Awards.savesReceived(by: owner.name)
    }

    private func statCard(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(label.uppercased())
                .font(.jakarta(10, .extraBold))
                .tracking(0.6)
                .foregroundStyle(Color.inkFaint)
            Text(value)
                .font(.gabarito(19, .extraBold))
                .foregroundStyle(accent ? Color.mango : Color.ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
    }

    private func toggleRow(
        icon: String, title: String, caption: String,
        isOn: Binding<Bool>, onChange: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.fill)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.ink)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.jakarta(14, .bold))
                    .foregroundStyle(Color.ink)
                Text(caption)
                    .font(.jakarta(12, .medium))
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.basil)
                .onChange(of: isOn.wrappedValue) { _, _ in onChange() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
    }
}

#Preview {
    ProfileSheet().modelContainer(SampleData.previewContainer)
}
