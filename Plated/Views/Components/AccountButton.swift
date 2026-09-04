import SwiftUI
import SwiftData

/// The consistent account door. Every screen opens the same small, explicit
/// hub; social profile and app administration no longer share one page.
struct AccountButton: View {
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @State private var showing = false

    private var owner: HouseholdMember? { members.first(where: \.isOwner) }

    var body: some View {
        Button {
            Haptic.tap()
            showing = true
        } label: {
            AvatarCircle(initials: owner?.initials ?? "Me", tone: .neutralPair, size: 42, photo: owner?.photoData)
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

/// One-tap account home. Profile is social identity; Settings is app behavior;
/// Household is the group. Naming those three doors removes the guessing that
/// came from putting a bare gear above an Instagram-shaped profile.
struct AccountHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @AppStorage("userBio") private var bio = ""

    @State private var sheet: AccountSheet?

    private var owner: HouseholdMember? { members.first(where: \.isOwner) }
    private var ownerName: String {
        guard let name = owner?.name, !HouseholdIdentity.isPlaceholder(name) else { return "Complete your profile" }
        return name
    }

    private enum AccountSheet: String, Identifiable {
        case edit, settings, household, profile
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                identity

                VStack(alignment: .leading, spacing: 10) {
                    MicroLabel("Your account")
                    accountAction(icon: "person.crop.circle", title: "Edit profile", caption: "Update your name, photo and bio.") { sheet = .edit }
                    accountAction(icon: "gearshape", title: "Settings", caption: "Appearance, reminders, calendar and sign-in.") { sheet = .settings }
                }

                VStack(alignment: .leading, spacing: 10) {
                    MicroLabel("Household & Table")
                    accountAction(icon: "house", title: "Your household", caption: "People, roles and the cook rotation.") { sheet = .household }
                    accountAction(icon: "rectangle.grid.3x2", title: "View your Table profile", caption: "Your posts, conversations and saved dishes.") { sheet = .profile }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .edit: EditProfileSheet()
            case .settings: SettingsSheet()
            case .household:
                NavigationStack {
                    HouseholdHomeView()
                        .safeAreaInset(edge: .top) {
                            HStack {
                                Text("Your household").plType(.heading)
                                Spacer()
                                DesignIconButton(symbol: "xmark", label: "Close household") { sheet = nil }
                            }
                            .padding(.horizontal, 24)
                            .background(Color.canvas)
                        }
                }
            case .profile:
                NavigationStack {
                    if let owner {
                        PersonProfileView(personName: owner.name, colorHex: owner.colorHex, memberID: owner.persistentModelID)
                    } else {
                        PersonProfileView(personName: "Me", colorHex: "", memberID: nil)
                    }
                }
            }
        }
    }

    private var topBar: some View {
        ZStack {
            Text("Account").plType(.heading, .semibold).foregroundStyle(Color.ink)
            HStack {
                Spacer()
                DesignIconButton(symbol: "xmark", label: "Close account") { dismiss() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.canvas.opacity(0.94))
    }

    private var identity: some View {
        HStack(spacing: 16) {
            AvatarCircle(initials: owner?.initials ?? "Me", tone: .neutralPair, size: 72, photo: owner?.photoData)
            VStack(alignment: .leading, spacing: 4) {
                Text(ownerName).plType(.title, .semibold).foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                MicroLabel(owner?.isOwner == true ? "Head of table" : "Your Plated account")
                if !bio.isEmpty {
                    Text(bio).plType(.footnote).foregroundStyle(Color.inkSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fill, in: Radius.shape(Radius.card))
        .padding(.top, 4)
    }

    private func accountAction(icon: String, title: String, caption: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.select()
            action()
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color.fill)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.ink)
                    }
                    .plChrome()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).plType(.body, .bold).foregroundStyle(Color.ink)
                    Text(caption).plType(.caption).foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
                    .plChrome()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(Radius.shape(Radius.card).strokeBorder(Color.hairline))
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("account-" + title.lowercased().replacingOccurrences(of: " ", with: "-"))
    }
}
