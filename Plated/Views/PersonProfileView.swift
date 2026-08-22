import SwiftUI
import SwiftData
import PhotosUI

/// A person at the table, Instagram-shaped: banner, avatar, stats, and a
/// grid of their plates. Pushed as a page — the back chevron is always
/// there, no sheet to guess at. Your own card adds Edit and Settings.
struct PersonProfileView: View {
    let personName: String
    let colorHex: String

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

    @AppStorage("userBio") private var myBio = ""
    @AppStorage("userFamilyName") private var userFamilyName = ""
    @State private var dmShown = false
    @State private var settingsShown = false
    @State private var editShown = false
    @State private var bannerItem: PhotosPickerItem?
    @State private var openedPost: TablePost?

    private var firstName: String {
        personName.split(separator: " ").first.map(String.init) ?? personName
    }

    private var member: HouseholdMember? {
        members.first { $0.name == personName || $0.name == firstName }
    }

    private var isMe: Bool { member?.isOwner ?? false }

    private var posts: [TablePost] {
        allPosts.filter { $0.kind == "dish" && ($0.authorName == personName || $0.firstName == firstName) }
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
                        Text(displayName)
                            .font(.gabarito(24, .extraBold))
                            .tracking(-0.4)
                            .foregroundStyle(Color.ink)
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

                    HStack(spacing: 0) {
                        statBlock("\(posts.count)", "Plates shared")
                        statBlock("\(plateCount)", "Plates earned")
                        statBlock("\(kissCount)", "Kisses", accent: kissCount > 0)
                        statBlock("\(Awards.savesReceived(by: personName))", "Saves")
                    }
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
                }
                .padding(.horizontal, 24)

                if posts.isEmpty {
                    VStack(spacing: 8) {
                        PlateReactionGlyph(filled: false)
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
            .padding(.bottom, 110)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
        .sheet(isPresented: $dmShown) { DMThreadView(peerName: personName) }
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
            .buttonStyle(.plain)
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
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
    }

    private var banner: some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = profiles.first?.bannerPhotoData, let image = UIImage(data: data), isMe {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
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
                .buttonStyle(.plain)
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
        .buttonStyle(.plain)
    }

    private func statBlock(_ value: String, _ label: String, accent: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.gabarito(19, .extraBold))
                .foregroundStyle(accent ? Color.mango : Color.ink)
            Text(label.uppercased())
                .font(.jakarta(8.5, .extraBold))
                .tracking(0.4)
                .foregroundStyle(Color.inkFaint)
        }
        .frame(maxWidth: .infinity)
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
        .buttonStyle(.plain)
    }

    private var initials: String {
        let parts = personName.split(separator: " ")
            .filter { $0.first?.isLetter == true }
            .prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private var displayName: String {
        if isMe && !userFamilyName.isEmpty && !personName.contains(" ") {
            return "\(personName) \(userFamilyName)"
        }
        return personName
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
    @AppStorage("userBio") private var bio = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit profile")
                .font(.gabarito(19, .extraBold))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Bio")
                TextField("What kind of cook are you?", text: $bio, axis: .vertical)
                    .font(.jakarta(14, .medium))
                    .lineLimit(2...4)
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
            }

            Text("Your photo comes from your table's eyes only for now — Apple doesn't share Apple ID pictures with apps, so profile photos arrive with Plated's own network.")
                .font(.jakarta(11, .medium))
                .foregroundStyle(Color.inkFaint)

            InkPillButton(title: "Done") { dismiss() }
            Spacer()
        }
        .padding(.horizontal, 24)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }
}

/// The settings drawer — where the light switch actually belongs. Quiet
/// controls, one card each: the room, the calendar, the subscription.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("afterDark") private var afterDark = false
    @AppStorage("showCalendarEvents") private var showCalendarEvents = false
    @State private var paywallShown = false
    @State private var plusActive = PlatedPlus.isActive

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("The back of house")
                Text("Settings")
                    .font(.gabarito(22, .extraBold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
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
                        .buttonStyle(.plain)
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
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
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
                    .font(.gabarito(26, .extraBold))
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
    var id: String { name }
}
