import SwiftUI
import SwiftData
import PhotosUI

/// A person at the table, Instagram-shaped: banner, avatar, stats, and a
/// grid of their plates. Pushed as a page — the back chevron is always
/// there, no sheet to guess at. Your own card adds Edit and Settings.
struct PersonProfileView: View {
    /// The name this page was pushed with. Read `name` instead of this
    /// anywhere the answer must stay current — see below.
    let personName: String
    let colorHex: String
    /// Identity, when the person is a seat here. A page keyed only on a
    /// name string goes stale the moment that name changes underneath it:
    /// the title reverts to "Me", the gear disappears, and "Edit profile"
    /// turns into "Message" pointing at a DM thread with yourself.
    var memberID: PersistentIdentifier?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query(filter: #Predicate<TablePost> { !$0.isDiscover }, sort: \TablePost.createdAt, order: .reverse)
    private var allPosts: [TablePost]
    @Query private var recipes: [Recipe]
    // Oldest first: two devices racing a first banner before sync merges
    // both insert a row, and an unsorted `.first` flips arbitrarily between
    // them per device. The oldest row is the household's one true profile.
    @Query(sort: \HouseholdProfile.createdAt) private var profiles: [HouseholdProfile]

    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("userBio") private var myBio = ""
    @AppStorage("userFamilyName") private var userFamilyName = ""
    @State private var dmShown = false
    @State private var settingsShown = false
    @State private var editShown = false
    @State private var bannerItem: PhotosPickerItem?
    @State private var openedPost: TablePost?

    /// Who this page is about, right now. Identity first, and only then
    /// the name it was pushed with.
    private var name: String { member?.name ?? personName }

    private var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    private var member: HouseholdMember? {
        if let memberID, let seated = members.first(where: { $0.persistentModelID == memberID }) {
            return seated
        }
        // Guests at the table have no seat to match — fall back to the name.
        let pushedFirst = personName.split(separator: " ").first.map(String.init) ?? personName
        return members.first { $0.name == personName || $0.name == pushedFirst }
    }

    private var isMe: Bool { member?.isOwner ?? false }

    private var posts: [TablePost] {
        allPosts.filter { $0.kind == "dish" && ($0.authorName == name || $0.firstName == firstName) }
    }

    private var kissCount: Int { posts.filter(\.hasChefsKiss).count }
    private var plateCount: Int { posts.reduce(0) { $0 + $1.totalPlates } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                banner
                    .overlay(alignment: .bottomLeading) {
                        AvatarCircle(
                            initials: initials,
                            tone: isMe ? .neutralPair : PersonTone.from(hex: colorHex),
                            size: 86
                        )
                        .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 4))
                        .offset(x: 24, y: 43)
                    }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Spacer()
                        if isMe {
                            outlineAction("Edit profile") { editShown = true }
                        } else {
                            outlineAction("Message") { dmShown = true }
                        }
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 3) {
                        // "Me" is what the bootstrap wrote when Apple gave
                        // us nothing — it's a prompt, not a name.
                        if isMe && HouseholdIdentity.isPlaceholder(name) {
                            Button {
                                Haptic.tap()
                                editShown = true
                            } label: {
                                HStack(spacing: 6) {
                                    Text("Add your name")
                                        .font(.gabarito(24, .semibold))
                                        .tracking(-0.4)
                                        .foregroundStyle(Color.ink)
                                    Image(systemName: "pencil")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.inkFaint)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel("Add your name")
                        } else {
                            Text(displayName)
                                .font(.gabarito(24, .semibold))
                                .tracking(-0.4)
                                .foregroundStyle(Color.ink)
                        }
                        MicroLabel(roleLine)
                        if isMe && !myBio.isEmpty {
                            Text(myBio)
                                .font(.jakarta(13, .medium))
                                .foregroundStyle(Color.inkSecondary)
                                .lineSpacing(3)
                                .padding(.top, 3)
                        }
                    }
                    .padding(.top, 26)

                    // Same count, same words, same lack of a box as Home
                    // and the stats shelf — a person's numbers and their
                    // household's numbers shouldn't be two dialects.
                    // Four across truncates from AX3 and collides at AX5
                    // ("On theHappy", "Chef's Saved", dividers no longer
                    // between columns). HouseholdStatsView already drops
                    // 3 columns to 2 at .accessibility1; this is the
                    // sibling that didn't, so it wraps to 2×2 instead.
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 0),
                            count: typeSize >= .accessibility1 ? 2 : 4
                        ),
                        spacing: typeSize >= .accessibility1 ? 16 : 0
                    ) {
                        CountBlock(value: "\(posts.count)", label: "On the table")
                        CountBlock(value: "\(plateCount)", label: "Happy plates")
                        CountBlock(value: "\(kissCount)", label: "Chef's kisses", accent: kissCount > 0)
                        CountBlock(value: "\(Awards.savesReceived(by: name))", label: "Saved by others")
                    }
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 24)

                if posts.isEmpty {
                    VStack(spacing: 8) {
                        PlateReactionGlyph(filled: false)
                            .plBreathing()
                        Text(isMe ? "Nothing shared yet — plate something for the table." : "\(firstName) hasn't shared a plate yet.")
                            .font(.jakarta(13, .medium))
                            .foregroundStyle(Color.inkFaint)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 44)
                    .padding(.horizontal, 40)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                        ForEach(posts, id: \.persistentModelID) { post in
                            postCell(post)
                        }
                    }
                    .padding(.top, 20)
                }
            }
            .padding(.bottom, Layout.floatingChromeInset)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
        .sheet(isPresented: $dmShown) { DMThreadView(peerName: name) }
        .sheet(isPresented: $settingsShown) { SettingsSheet() }
        .sheet(isPresented: $editShown) { EditProfileSheet() }
        .navigationDestination(item: $openedPost) { post in
            PostThreadView(post: post)
        }
        .onChange(of: bannerItem) { _, item in
            guard let item else { return }
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self) {
                    setBanner(raw)
                }
            }
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button {
                Haptic.tap()
                dismiss()
            } label: {
                Circle()
                    .fill(Color.canvas.opacity(0.9))
                    .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1.5))
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            Spacer()
            if isMe {
                Button {
                    Haptic.tap()
                    settingsShown = true
                } label: {
                    Circle()
                        .fill(Color.canvas.opacity(0.9))
                        .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1.5))
                        .frame(width: 38, height: 38)
                        .overlay {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ink)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
    }

    private var banner: some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = profiles.first?.bannerPhotoData, let image = UIImage(data: data), isMe {
                PhotoWell(image: image, height: 150, cornerRadius: 0)
            } else {
                LinearGradient(
                    colors: [PersonTone.from(hex: colorHex).tint, Color.canvas],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 150)
            }
            if isMe {
                PhotosPicker(selection: $bannerItem, matching: .images) {
                    HStack(spacing: 5) {
                        Image(systemName: "camera")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Banner")
                            .font(.jakarta(11, .bold))
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func postCell(_ post: TablePost) -> some View {
        Button {
            Haptic.tap()
            openedPost = post
        } label: {
            GeometryReader { proxy in
                if let data = post.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.width)
                        .clipped()
                } else {
                    Color.fill
                        .overlay {
                            PlateReactionGlyph(filled: false)
                        }
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.pressable)
    }

    private func outlineAction(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Text(label)
                .font(.jakarta(13, .bold))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    private var initials: String {
        let parts = name.split(separator: " ")
            .filter { $0.first?.isLetter == true }
            .prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private var displayName: String {
        if isMe && !userFamilyName.isEmpty && !name.contains(" ") {
            return "\(name) \(userFamilyName)"
        }
        return name
    }

    private var roleLine: String {
        if isMe { return "Host · Head of table" }
        if let member { return member.roleLine.isEmpty ? member.role.capitalized : member.roleLine }
        return "At your table"
    }

    private func setBanner(_ raw: Data) {
        let processed = Self.downscale(raw)
        if let profile = profiles.first {
            profile.bannerPhotoData = processed
        } else {
            context.insert(HouseholdProfile(bannerPhotoData: processed))
        }
    }

    static func downscale(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1400
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.75)
    }
}

/// Name and bio, nothing else — the profile stays light.
struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @AppStorage("userBio") private var bio = ""
    @AppStorage("userFirstName") private var firstName = ""
    @State private var draftName = ""
    @FocusState private var namingSelf: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit profile")
                .font(.gabarito(19, .bold))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Your name")
                TextField("Nate", text: $draftName)
                    .font(.jakarta(14, .semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.chip))
                    .onTapGesture { namingSelf = true }
                    .focused($namingSelf)
                    .submitLabel(.done)
            }

            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Bio")
                TextField("What kind of cook are you?", text: $bio, axis: .vertical)
                    .font(.jakarta(14, .medium))
                    .lineLimit(2...4)
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
            }

            Text("Apple shares your name once, when you first sign in, and never again — so if Plated is calling you \"Me\", this is where you fix it. Photos aren't shared by Apple at all; they arrive with Plated's own network.")
                .font(.jakarta(11, .medium))
                .foregroundStyle(Color.inkFaint)

            InkPillButton(title: "Done") {
                saveName()
                dismiss()
            }
            Spacer()
        }
        .onAppear {
            let owner = members.first(where: \.isOwner)?.name ?? firstName
            draftName = HouseholdIdentity.isPlaceholder(owner) ? "" : owner
        }
        .padding(.horizontal, 24)
        .presentationDetents([.height(430), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    /// The name lives in two places — the preference the app reads for
    /// authorship and the owner's own row at the table. Both or neither.
    private func saveName() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        // The model side FIRST, and `userFirstName` only once it stuck.
        // This used to write the AppStorage name before renaming, so a
        // failed save left the models back at "Me" while the stored first
        // name and the awards ledger had moved on — the profile reading
        // "Me" with no saves, while every new comment was stamped with the
        // new name. Identity split across two stores, and nothing told
        // anyone.
        if let owner = members.first(where: \.isOwner) {
            // Through the one door: a bare `owner.name = name` orphans
            // every dish they have posted and their whole awards ledger.
            guard HouseholdIdentity.rename(owner, to: name, in: context) else {
                Haptic.warn()
                return
            }
        }
        firstName = name
        Haptic.plate()
    }
}

/// The settings drawer — where the light switch actually belongs. Quiet
/// controls, one card each: the room, the calendar, the subscription.
struct SettingsSheet: View {
    /// Set when Settings is opened from Home's "Your Household" title —
    /// the user asked to name the house, so put them in the field.
    var focusHouseholdName = false

    @Environment(\.dismiss) private var dismiss
    @AppStorage("afterDark") private var afterDark = false
    @AppStorage("showCalendarEvents") private var showCalendarEvents = false
    @AppStorage("householdName") private var householdName = ""
    @State private var paywallShown = false
    @State private var plusActive = PlatedPlus.isActive
    @FocusState private var namingHousehold: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("The back of house")
                Text("Settings")
                    .font(.gabarito(22, .semibold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    // Apple hands over a family name once, at first sign-in,
                    // and only with permission — so the house has to be
                    // nameable by hand or it stays "Your Household" forever.
                    settingRow(
                        icon: "house",
                        title: "Household name",
                        caption: "The family name on your Home page."
                    ) {
                        TextField("Meadows", text: $householdName)
                            .font(.jakarta(14, .bold))
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .overlay(Capsule().strokeBorder(Color.hairline))
                            // Padding alone isn't hit-testable — the field
                            // was a ~19pt strip you had to aim at.
                            .contentShape(Capsule())
                            .onTapGesture { namingHousehold = true }
                            .focused($namingHousehold)
                            .submitLabel(.done)
                            .onSubmit { namingHousehold = false }
                    }

                    settingRow(
                        icon: afterDark ? "moon.stars.fill" : "moon",
                        title: "After Dark",
                        caption: "The warm room. Photos glow, chrome sleeps."
                    ) {
                        Toggle("", isOn: $afterDark)
                            .labelsHidden()
                            .tint(Color.basil)
                            .onChange(of: afterDark) { _, _ in Haptic.plate() }
                    }

                    settingRow(
                        icon: "calendar",
                        title: "Calendar on the plan",
                        caption: "Show Apple Calendar events next to each night."
                    ) {
                        Toggle("", isOn: $showCalendarEvents)
                            .labelsHidden()
                            .sensoryFeedback(.selection, trigger: showCalendarEvents)
                            .tint(Color.basil)
                            .onChange(of: showCalendarEvents) { _, on in
                                if on {
                                    Task {
                                        let granted = await DayEventsProvider.shared.requestAccess()
                                        if !granted { showCalendarEvents = false }
                                    }
                                }
                            }
                    }

                    if PlatedPlus.gatingEnabled {
                        Button {
                            Haptic.tap()
                            paywallShown = true
                        } label: {
                            settingRow(
                                icon: "plus.circle",
                                title: "Plated+",
                                caption: plusActive ? "Active — the whole household is seated." : "Seat the whole household and everything next."
                            ) {
                                Text(plusActive ? "ACTIVE" : "JOIN")
                                    .font(.jakarta(11, .extraBold))
                                    .tracking(0.5)
                                    .foregroundStyle(plusActive ? Color.basil : Color.tomato)
                            }
                        }
                        .buttonStyle(.pressable)
                    }

                    Text("Plated 0.1.0 · Made at the table")
                        .font(.jakarta(11, .medium))
                        .foregroundStyle(Color.inkFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .onAppear {
            if focusHouseholdName { namingHousehold = true }
        }
        .sheet(isPresented: $paywallShown, onDismiss: { plusActive = PlatedPlus.isActive }) {
            PaywallSheet()
        }
    }

    private func settingRow(
        icon: String, title: String, caption: String,
        @ViewBuilder trailing: () -> some View
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
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
    }
}

/// Plated+ — the one paywall. Seats beyond the head of table live here.
/// Honest about its stage: no StoreKit products exist yet, so the CTA
/// activates a preview flag and says so out loud.
struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var active = PlatedPlus.isActive

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.fill)
                        .frame(width: 64, height: 64)
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.ink)
                }
                Text("Plated+")
                    .font(.gabarito(26, .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Color.ink)
                Text("One seat is free — the head of table. Plated+ seats everyone else.")
                    .font(.jakarta(13, .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .padding(.top, 30)
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 12) {
                perk("person.2", "Unlimited household seats", "Partners, kids, grandma — everyone gets a color.")
                perk("calendar", "The whole plan, shared", "Everyone sees the week and their nights.")
                perk("bubble.left.and.bubble.right", "Table talk", "Comments, asks, polls, and DMs with your people.")
                perk("sparkles", "First in line", "New features land on Plated+ tables first.")
            }
            .padding(.horizontal, 30)

            Spacer()

            VStack(spacing: 8) {
                if active {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.basil)
                        Text("Plated+ is active on this table")
                            .font(.jakarta(14, .bold))
                            .foregroundStyle(Color.ink)
                    }
                    .frame(height: 56)
                } else {
                    TomatoPillButton(title: "Start Plated+ · $2.99/mo") {
                        PlatedPlus.isActive = true
                        withAnimation(.plPop) { active = true }
                        Haptic.kiss()
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            dismiss()
                        }
                    }
                    Text("Preview build: activates instantly. Real checkout arrives with App Store Connect setup.")
                        .font(.jakarta(10, .medium))
                        .foregroundStyle(Color.inkFaint)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    private func perk(_ icon: String, _ title: String, _ caption: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.jakarta(14, .bold))
                    .foregroundStyle(Color.ink)
                Text(caption)
                    .font(.jakarta(12, .medium))
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }
}

/// A lightweight handle for pushing someone's profile page.
struct PersonRef: Identifiable, Hashable {
    let name: String
    let colorHex: String
    /// Set whenever the person is a seat at this household. A name is a
    /// label and labels change; the page follows the identity so a rename
    /// while you are looking at your own profile updates it instead of
    /// stranding you on a stale stranger.
    var memberID: PersistentIdentifier?
    var id: String { memberID.map { "\($0.hashValue)" } ?? name }

    /// Build a ref for a name that may or may not belong to a seat here —
    /// a post's author, a comment's, an @mention.
    ///
    /// **Always use this rather than the memberwise init when starting
    /// from a name.** Resolving the seat at construction is the entire
    /// reason the profile page survives a rename: a ref carrying only a
    /// string strands the moment that string changes, and the page falls
    /// back to matching on a name that no longer exists. Two of the six
    /// construction sites were built by hand and missed the id, which
    /// reproduced the whole original symptom set — title reverting to
    /// "Me", the gear vanishing, "Edit profile" becoming a DM with
    /// yourself — on the most ordinary path in the app.
    static func author(
        _ name: String,
        colorHex: String,
        in members: [HouseholdMember]
    ) -> PersonRef {
        let first = name.split(separator: " ").first.map(String.init) ?? name
        let seat = members.first { $0.name == name || $0.name == first }
        return PersonRef(
            name: name,
            colorHex: colorHex,
            memberID: seat?.persistentModelID
        )
    }
}
