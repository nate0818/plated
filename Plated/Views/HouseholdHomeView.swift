import SwiftUI
import SwiftData

/// Home — the household itself. One head of table owns the account;
/// everyone else gets a seat, a color, and maybe a night to cook.
struct HouseholdHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var recipes: [Recipe]
    @Query(filter: #Predicate<TablePost> { !$0.isDiscover }) private var posts: [TablePost]

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("autoRotateOpenNights") private var autoRotate = true
    @AppStorage("afterDark") private var afterDark = false
    @AppStorage("userFamilyName") private var userFamilyName = ""
    @State private var addPresented = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 2) {
                    MicroLabel(familyLabel)
                    Text("Your household")
                        .font(.gabarito(28, .extraBold))
                        .tracking(-0.6)
                        .foregroundStyle(Color.ink)
                }

                membersCard

                insightsSection

                VStack(alignment: .leading, spacing: 10) {
                    MicroLabel("Who cooks when")
                    cookGrid
                    Text("Tap a day to pass it around. Open days ask the household for ideas.")
                        .font(.jakarta(12, .medium))
                        .foregroundStyle(Color.inkFaint)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Take turns automatically")
                                .font(.jakarta(14, .bold))
                                .foregroundStyle(Color.ink)
                            Text("Rotate open days between everyone")
                                .font(.jakarta(12, .medium))
                                .foregroundStyle(Color.inkSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $autoRotate)
                            .labelsHidden()
                            .tint(Color.basil)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
                    .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 10) {
                    MicroLabel("The room")
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.fill)
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: afterDark ? "moon.stars.fill" : "moon")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(afterDark ? Color.ink : Color.inkSecondary)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("After Dark")
                                .font(.jakarta(14, .bold))
                                .foregroundStyle(Color.ink)
                            Text("The warm room. Photos glow, chrome sleeps.")
                                .font(.jakarta(12, .medium))
                                .foregroundStyle(Color.inkSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $afterDark.animation(.plSettle))
                            .labelsHidden()
                            .tint(Color.basil)
                            .onChange(of: afterDark) { _, _ in Haptic.plate() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
                }

                Button {
                    Haptic.tap()
                    addPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text("Add someone to the household")
                            .font(.jakarta(15, .bold))
                    }
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .overlay {
                        Capsule().strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 110)
        }
        .background(alignment: .topTrailing) {
            // After Dark lets the chrome sleep — no ambient glow in the dark room.
            if colorScheme == .light {
                RadialGradient(colors: [.basilTint, .basilTint.opacity(0)], center: .center, startRadius: 0, endRadius: 220)
                    .frame(width: 440, height: 440)
                    .offset(x: 140, y: -160)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $addPresented) {
            AddMemberSheet()
        }
    }

    private var familyLabel: String {
        guard !userFamilyName.isEmpty else { return "Your table" }
        // "Meadows" stays "The Meadows"; "Chen" becomes "The Chens".
        return userFamilyName.lowercased().hasSuffix("s")
            ? "The \(userFamilyName)"
            : "The \(userFamilyName)s"
    }

    // MARK: Insights
    // The trophy shelf — what this table has earned, counted quietly.

    private var kissCount: Int { posts.filter(\.hasChefsKiss).count }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel("Your table, counted")
            HStack(spacing: 8) {
                insightTile("Kisses", "\(kissCount)", symbol: "sparkles", accent: kissCount > 0)
                insightTile("Recipes", "\(recipes.count)", symbol: "book.closed")
                insightTile("Posts", "\(posts.count)", symbol: "circle.circle")
                insightTile("Saves", "\(Awards.totalSavesRecorded)", symbol: "arrow.down.heart")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    milestoneChip("First recipe", earned: !recipes.isEmpty)
                    milestoneChip("First table post", earned: posts.contains { $0.kind == "dish" })
                    milestoneChip("First chef's kiss", earned: kissCount > 0)
                    milestoneChip("Full table", earned: members.count >= 3)
                    milestoneChip("First save", earned: Awards.totalSavesRecorded > 0)
                }
            }
        }
    }

    private func insightTile(_ label: String, _ value: String, symbol: String, accent: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent ? Color.mango : Color.inkFaint)
            Text(value)
                .font(.gabarito(19, .extraBold))
                .foregroundStyle(Color.ink)
            Text(label.uppercased())
                .font(.jakarta(9, .extraBold))
                .tracking(0.5)
                .foregroundStyle(Color.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
    }

    private func milestoneChip(_ label: String, earned: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: earned ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(earned ? Color.basil : Color.inkFaint)
            Text(label)
                .font(.jakarta(12, .bold))
                .foregroundStyle(earned ? Color.ink : Color.inkFaint)
        }
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background {
            if earned {
                Capsule().fill(Color.basilTint)
            } else {
                Capsule().strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
        }
    }

    private var membersCard: some View {
        VStack(spacing: 0) {
            ForEach(members, id: \.persistentModelID) { member in
                memberRow(member)
                if member.persistentModelID != members.last?.persistentModelID {
                    Divider().overlay(Color.hairlineSoft)
                }
            }
        }
        .padding(.horizontal, 18)
        .background(Color.canvas)
        .clipShape(RoundedRectangle(cornerRadius: Radius.hero))
        .overlay(RoundedRectangle(cornerRadius: Radius.hero).strokeBorder(Color.hairline))
        .plCardShadow()
    }

    private func memberRow(_ member: HouseholdMember) -> some View {
        HStack(spacing: 12) {
            AvatarCircle(
                initials: member.firstInitial,
                tone: member.isOwner ? .neutralPair : member.tone,
                size: 46
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(member.name)
                    .font(.jakarta(15, .bold))
                    .foregroundStyle(Color.ink)
                if member.isOwner {
                    Text("HEAD OF TABLE")
                        .font(.jakarta(12, .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.inkSecondary)
                } else {
                    Text(member.roleLine.isEmpty ? member.role.capitalized : member.roleLine)
                        .font(.jakarta(12, .semibold))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer()
            if member.isOwner {
                Text("Owns the account")
                    .font(.jakarta(12, .bold))
                    .foregroundStyle(Color.inkFaint)
            } else if !member.cookWeekdays.isEmpty {
                Text(dayChipLabel(member))
                    .font(.jakarta(12, .bold))
                    .foregroundStyle(member.tone.tone)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(member.tone.tint, in: Capsule())
            }
        }
        .padding(.vertical, 12)
    }

    private var cookGrid: some View {
        let today = Calendar.current.component(.weekday, from: .now)
        return HStack(spacing: 6) {
            ForEach(weekdaysFromToday, id: \.self) { weekday in
                cookCell(weekday: weekday, isToday: weekday == today)
            }
        }
    }

    private func cookCell(weekday: Int, isToday: Bool) -> some View {
        let cook = members.first { $0.cookWeekdays.contains(weekday) }
        return Button {
            cycleCook(weekday: weekday)
        } label: {
            VStack(spacing: 6) {
                Text(shortDay(weekday).uppercased())
                    .font(.jakarta(10, .extraBold))
                    .tracking(0.4)
                    .foregroundStyle(isToday ? Color.tomato : Color.inkFaint)
                if let cook {
                    AvatarCircle(initials: cook.firstInitial, tone: cook.tone, size: 28)
                } else {
                    Circle()
                        .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        .frame(width: 28, height: 28)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isToday ? Color.todayTint : Color.canvas)
            .clipShape(RoundedRectangle(cornerRadius: Radius.chip))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.chip)
                    .strokeBorder(isToday ? Color.tomato : Color.hairline, lineWidth: isToday ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    /// Cook grid runs today-first, matching the week screen.
    private var weekdaysFromToday: [Int] {
        let today = Calendar.current.component(.weekday, from: .now)
        return (0..<7).map { (today - 1 + $0) % 7 + 1 }
    }

    private func shortDay(_ weekday: Int) -> String {
        Calendar.current.shortWeekdaySymbols[weekday - 1]
    }

    private func dayChipLabel(_ member: HouseholdMember) -> String {
        if member.cookWeekdays.count == 1, let day = member.cookWeekdays.first {
            return "\(Calendar.current.weekdaySymbols[day - 1])s"
        }
        let today = Calendar.current.component(.weekday, from: .now)
        return member.cookWeekdays
            .sorted { (($0 - today + 7) % 7) < (($1 - today + 7) % 7) }
            .map { shortDay($0) }
            .joined(separator: " + ")
    }

    /// Tap a day: hand it to the next person around the table, or open it up.
    private func cycleCook(weekday: Int) {
        Haptic.tap()
        let current = members.firstIndex { $0.cookWeekdays.contains(weekday) }
        withAnimation(.plPop) {
            if let current {
                members[current].cookWeekdays.removeAll { $0 == weekday }
                let next = current + 1
                if next < members.count {
                    members[next].cookWeekdays.append(weekday)
                }
                // Past the last member the day goes open.
            } else if let first = members.first {
                first.cookWeekdays.append(weekday)
            }
        }
    }
}

/// New seat at the household table — name, role, and the next color around
/// the rotation.
struct AddMemberSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var members: [HouseholdMember]

    @State private var name = ""
    @State private var role = "partner"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add to the household")
                .font(.gabarito(19, .extraBold))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

            TextField("Their name", text: $name)
                .font(.jakarta(16, .semibold))
                .padding(14)
                .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))

            HStack(spacing: 8) {
                roleChip("partner", "Partner")
                roleChip("kid", "Kid")
                roleChip("member", "Guest")
            }

            TomatoPillButton(title: "Set their place") {
                let color = PersonTone.rotation[members.count % PersonTone.rotation.count]
                let line = role == "partner" ? "Partner · plans & cooks"
                    : role == "kid" ? "Kid · ideas & helping" : "Guest of the table"
                context.insert(HouseholdMember(
                    name: name.trimmingCharacters(in: .whitespaces),
                    colorHex: color, role: role, roleLine: line
                ))
                dismiss()
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            Spacer()
        }
        .padding(.horizontal, 24)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    private func roleChip(_ value: String, _ label: String) -> some View {
        let active = role == value
        return Button {
            Haptic.tap()
            withAnimation(.plSnap) { role = value }
        } label: {
            Text(label)
                .font(.jakarta(13, .bold))
                .foregroundStyle(active ? Color.canvas : Color.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    if active {
                        Capsule().fill(Color.ink)
                    } else {
                        Capsule().strokeBorder(Color.hairline)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
