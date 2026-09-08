import SwiftUI
import SwiftData

/// The consistent account door. Every primary screen opens this same place.
struct AccountButton: View {
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @State private var showing = false

    private var me: HouseholdMember? { members.me }

    var body: some View {
        Button {
            Haptic.tap()
            showing = true
        } label: {
            AvatarCircle(
                initials: me?.initials ?? "Me",
                tone: .neutralPair,
                size: 42,
                photo: me?.photoData
            )
            .overlay(Circle().strokeBorder(Color.canvas.opacity(0.9), lineWidth: 2))
            .shadow(color: Color.shadowInk.opacity(0.10), radius: 8, y: 3)
            .plTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account")
        .accessibilityHint("Opens your profile, household and settings.")
        .sheet(isPresented: $showing) {
            NavigationStack { AccountHomeView() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.canvas)
                .presentationCornerRadius(Radius.sheet)
                .plTapOutsideToDismiss()
        }
    }
}

/// A personal control center rather than a menu of administrative pages.
/// Identity is the first thing a person sees; status is glanceable; the two
/// places they manage most often are large, distinct targets.
struct AccountHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query(sort: \PlannedMeal.date) private var plannedMeals: [PlannedMeal]
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Query(sort: \TablePost.createdAt, order: .reverse) private var tablePosts: [TablePost]
    @AppStorage("userBio") private var bio = ""
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("remindersOn") private var remindersOn = true
    @AppStorage("householdName") private var householdName = ""

    @State private var sheet: AccountSheet?
    @State private var sync = SyncStatus.shared
    @State private var remindersAllowed = false
    @State private var awards: [PlatedAward] = []

    private var me: HouseholdMember? { members.me }
    private var ownerName: String {
        guard let name = me?.name, !HouseholdIdentity.isPlaceholder(name) else {
            return "Complete your profile"
        }
        return name
    }
    private var awardsIdentityName: String { me?.name ?? "Me" }
    private var appearance: Appearance {
        Appearance(rawValue: appearanceRaw) ?? .system
    }

    private enum AccountSheet: String, Identifiable {
        case edit, settings, household, profile, awards
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    MicroLabel("Your Plated")
                    Text("Your place at the table.")
                        .plType(.title, .semibold)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                identityHero

                VStack(alignment: .leading, spacing: 12) {
                    MicroLabel("Your spaces")
                    VStack(spacing: 10) {
                        spaceCard(
                            icon: "house.fill",
                            eyebrow: householdEyebrow,
                            title: householdTitle,
                            caption: "People, roles and cook rotation.",
                            tint: .basilTint,
                            tone: .completion,
                            identifier: "account-your-household"
                        ) { sheet = .household }

                        spaceCard(
                            icon: "slider.horizontal.3",
                            eyebrow: "Preferences",
                            title: "Settings",
                            caption: "Plan, permissions and appearance.",
                            tint: .mangoTint,
                            tone: .amber,
                            identifier: "account-settings"
                        ) { sheet = .settings }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    MicroLabel("Your awards")
                    AwardsPreviewCard(awards: awards) { sheet = .awards }
                        .accessibilityIdentifier("account-awards")
                }

                VStack(alignment: .leading, spacing: 12) {
                    MicroLabel("At a glance")
                    statusCard
                }

                Text("Plated \(Self.versionLine)")
                    .plType(.micro, .medium)
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 32)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
        .task {
            await sync.refresh()
            remindersAllowed = await NotificationScheduler.authorized()
            refreshAwards()
        }
        .task(id: awardActivitySignature) { refreshAwards() }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .edit:
                EditProfileSheet()
            case .settings:
                SettingsSheet()
            case .household:
                NavigationStack {
                    HouseholdHomeView()
                        .safeAreaInset(edge: .top) {
                            HStack {
                                Text("Your household").plType(.heading)
                                Spacer()
                                DesignIconButton(symbol: "xmark", label: "Close household") {
                                    sheet = nil
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                        }
                }
            case .profile:
                NavigationStack {
                    if let me {
                        PersonProfileView(
                            personName: me.name,
                            colorHex: me.colorHex,
                            memberID: me.persistentModelID
                        )
                    } else {
                        PersonProfileView(personName: "Me", colorHex: "", memberID: nil)
                    }
                }
            case .awards:
                NavigationStack {
                    AwardsGalleryView(personName: ownerName, awards: awards)
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    PlatedWordmark(size: 19)
                    Text("Account")
                        .plType(.footnote, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
                PlatedWordmark(size: 19)
            }
            Spacer()
            DesignIconButton(symbol: "xmark", label: "Close account") { dismiss() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }

    private var identityHero: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color.tomato.opacity(0.10))
                .frame(width: 180, height: 180)
                .offset(x: 56, y: -76)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    AvatarCircle(
                        initials: me?.initials ?? "Me",
                        tone: .neutralPair,
                        size: 82,
                        photo: me?.photoData
                    )
                    .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 4))
                    .shadow(color: Color.shadowWarm.opacity(0.16), radius: 14, y: 7)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(ownerName)
                            .plName()
                            .plType(.title, .semibold)
                            .foregroundStyle(Color.ink)
                        MicroLabel(me?.isOwner == true ? "Head of table" : "Your account")
                        if !bio.isEmpty {
                            Text(bio)
                                .plType(.caption)
                                .foregroundStyle(Color.inkSecondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }

                Group {
                    if typeSize >= .xxLarge {
                        VStack(spacing: 10) { profileButton; editButton }
                    } else {
                        HStack(spacing: 10) { profileButton; editButton }
                    }
                }
            }
            .padding(20)
        }
        .clipShape(Radius.shape(Radius.hero))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.tomatoTint, Color.raisedFill],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Radius.shape(Radius.hero)
        )
        .overlay(Radius.shape(Radius.hero).strokeBorder(Color.tomato.opacity(0.13)))
        .shadow(color: Color.shadowWarm.opacity(0.10), radius: 22, y: 10)
    }

    private var profileButton: some View {
        Button {
            Haptic.select()
            sheet = .profile
        } label: {
            Label("Profile", systemImage: "person.crop.circle")
                .plType(.footnote, .bold)
                .plActionLabel()
                .foregroundStyle(Color.onTomato)
                .padding(.horizontal, 17)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.tomato, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("account-view-your-table-profile")
        .accessibilityLabel("View your Table profile")
    }

    private var editButton: some View {
        Button {
            Haptic.select()
            sheet = .edit
        } label: {
            Label("Edit", systemImage: "pencil")
                .plType(.footnote, .bold)
                .plActionLabel()
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 17)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("account-edit-profile")
    }

    private var householdEyebrow: String {
        "\(members.count) \(members.count == 1 ? "person" : "people")"
    }

    private var householdTitle: String {
        let trimmed = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Household" : trimmed
    }

    private var awardActivitySignature: String {
        let cooked = plannedMeals.filter { $0.cookedAt != nil }.count
        let plates = tablePosts.reduce(0) { $0 + $1.totalPlates }
        return "\(plannedMeals.count).\(cooked).\(recipes.count).\(tablePosts.count).\(plates).\(members.count)"
    }

    private func refreshAwards() {
        let metrics = Awards.metrics(
            for: me,
            meals: plannedMeals,
            recipes: recipes,
            posts: tablePosts,
            householdSize: members.count
        )
        awards = Awards.evaluate(metrics, for: awardsIdentityName)
    }

    private func spaceCard(
        icon: String,
        eyebrow: String,
        title: String,
        caption: String,
        tint: Color,
        tone: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptic.select()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tone)
                    .frame(width: 44, height: 44)
                    .background(tint, in: Circle())
                    .plChrome()

                VStack(alignment: .leading, spacing: 4) {
                    MicroLabel(eyebrow)
                    Text(title)
                        .plName()
                        .plType(.heading, .semibold)
                        .foregroundStyle(Color.ink)
                    Text(caption)
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(Color.raisedFill, in: Radius.shape(Radius.card))
            .overlay(Radius.shape(Radius.card).strokeBorder(Color.hairline))
            .contentShape(Radius.shape(Radius.card))
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier(identifier)
    }

    private var statusCard: some View {
        Button {
            Haptic.select()
            sheet = .settings
        } label: {
            VStack(spacing: 0) {
                statusRow(
                    symbol: sync.account.isSyncing ? "icloud.fill" : "icloud",
                    title: "iCloud",
                    value: syncValue,
                    tint: sync.account.line == nil ? .basilTint : .mangoTint,
                    tone: sync.account.line == nil ? .completion : .amber
                )
                Divider().overlay(Color.hairlineSoft).padding(.leading, 64)
                statusRow(
                    symbol: remindersAllowed && remindersOn ? "bell.badge.fill" : "bell.slash",
                    title: "Cook reminders",
                    value: remindersAllowed && remindersOn ? "On" : "Off",
                    tint: .tomatoTint,
                    tone: .tomato
                )
                Divider().overlay(Color.hairlineSoft).padding(.leading, 64)
                statusRow(
                    symbol: appearance == .dark ? "moon.stars.fill" : appearance == .light ? "sun.max.fill" : "circle.lefthalf.filled",
                    title: "Appearance",
                    value: appearance.label,
                    tint: .fill,
                    tone: .ink
                )
            }
            .background(Color.raisedFill, in: Radius.shape(Radius.card))
            .overlay(Radius.shape(Radius.card).strokeBorder(Color.hairline))
            .contentShape(Radius.shape(Radius.card))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Settings summary. iCloud \(syncValue), reminders \(remindersAllowed && remindersOn ? "on" : "off"), appearance \(appearance.label).")
    }

    private func statusRow(
        symbol: String,
        title: String,
        value: String,
        tint: Color,
        tone: Color
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tone)
                .frame(width: 34, height: 34)
                .background(tint, in: Circle())
                .plChrome()
            if typeSize >= .accessibility1 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .plType(.body, .semibold)
                        .foregroundStyle(Color.ink)
                    Text(value)
                        .plType(.caption, .medium)
                        .foregroundStyle(Color.inkSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(title)
                    .plType(.body, .semibold)
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 8)
                Text(value)
                    .plType(.footnote, .medium)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, typeSize >= .accessibility1 ? 12 : 0)
        .frame(minHeight: 62)
    }

    private var syncValue: String {
        switch sync.account {
        case .available: return "Up to date"
        case .notArmed: return "On this iPhone"
        case .noAccount, .restricted, .temporarilyUnavailable: return "Needs attention"
        }
    }

    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
