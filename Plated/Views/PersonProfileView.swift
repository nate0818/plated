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
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    // An author is the one thing every real post has. The empty-name
    // rows are blanks the CloudKit mirror adopts (TablePost.isBlank),
    // and counting them puts a dish on the board nobody cooked.
    @Query(filter: #Predicate<TablePost> { !$0.isDiscover && !$0.authorName.isEmpty }, sort: \TablePost.createdAt, order: .reverse)
    private var allPosts: [TablePost]
    @Query private var recipes: [Recipe]
    // Oldest first: two devices racing a first banner before sync merges
    // both insert a row, and an unsorted `.first` flips arbitrarily between
    // them per device. The oldest row is the household's one true profile.
    @Query(sort: \HouseholdProfile.createdAt) private var profiles: [HouseholdProfile]

    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("userBio") private var myBio = ""
    @AppStorage("userFamilyName") private var userFamilyName = ""
    @State private var settingsShown = false
    @State private var editShown = false
    @State private var bannerItem: PhotosPickerItem?
    @State private var openedPost: TablePost?
    /// The grid tile you touched is the thread that opens. One source per
    /// post, so the tile's own id is unambiguous here.
    @Namespace private var zoom

    /// Who this page is about, right now. Identity first, and only then
    /// the name it was pushed with.
    private var name: String { member?.name ?? personName }

    private var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    /// What "nothing here" means depends on who they are. A kid who will
    /// never post is not the same silence as somebody who joined last week.
    private var emptyLine: String {
        if isMe { return "Nothing shared yet." }
        switch member?.seat {
        case .invited:
            return "\(firstName) hasn't taken their seat yet."
        case .notOnPlated:
            return "\(firstName) isn't on Plated. This is the place you keep for them."
        default:
            return "\(firstName) hasn't shared a plate yet."
        }
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

    private var kissCount: Int { posts.filter { $0.hasChefsKiss(seats: members.count) }.count }
    private var plateCount: Int { posts.reduce(0) { $0 + $1.totalPlates } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                banner
                    .overlay(alignment: .bottomLeading) {
                        AvatarCircle(
                            initials: initials,
                            tone: isMe ? .neutralPair : PersonTone.from(hex: colorHex),
                            size: 86,
                            photo: member?.photoData
                        )
                        .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 4))
                        .offset(x: 24, y: 43)
                    }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Spacer()
                        if isMe {
                            outlineAction("Edit profile") { editShown = true }
                        } else if let url = member?.messageURL {
                            // Only where a message can actually go. This used
                            // to open a thread that could never deliver.
                            outlineAction("Message") { openURL(url) }
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
                                        .plType(.title)
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
                                .plName()
                                .plType(.title)
                                .foregroundStyle(Color.ink)
                        }
                        MicroLabel(roleLine)
                        if isMe && !myBio.isEmpty {
                            Text(myBio)
                                .plType(.footnote)
                                .foregroundStyle(Color.inkSecondary)
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
                        CountBlock(value: "\(posts.count)", label: "Posts")
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
                        Text(emptyLine)
                            .plType(.footnote)
                            .foregroundStyle(Color.inkSecondary)
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
        .plSwipeBack()
        .safeAreaInset(edge: .top) { topBar }
        .sheet(isPresented: $settingsShown) { SettingsSheet() }
        .sheet(isPresented: $editShown) { EditProfileSheet() }
        .navigationDestination(item: $openedPost) { post in
            PostThreadView(post: post)
                .navigationTransition(.zoom(sourceID: post.persistentModelID, in: zoom))
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
                            .accessibilityLabel("Back")
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
                                .accessibilityLabel("Settings")
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
                        Text("Change")
                            .plType(.micro)
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
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
        .matchedTransitionSource(id: post.persistentModelID, in: zoom)
    }

    private func outlineAction(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Text(label)
                .plType(.footnote, .bold)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
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
        if isMe { return "Head of table" }
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
    @State private var photoData: Data?
    @State private var pickerItem: PhotosPickerItem?
    /// Why the last Done didn't take. A refusal that only buzzes is a
    /// refusal the user can't act on.
    @State private var nameError: String?
    @FocusState private var namingSelf: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit profile")
                // .title at 22, like Settings one sheet away.
                .plType(.title)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                VStack(spacing: 8) {
                    ProfilePhotoWell(photoData: $photoData, initials: draftInitials, diameter: 96)
                    Text(photoData == nil ? "Add your photo" : "Change your photo")
                        .plType(.caption, .bold)
                        .foregroundStyle(Color.inkSecondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pressable)

            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Your name")
                TextField("First name", text: $draftName)
                    .plType(.body)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .onTapGesture { namingSelf = true }
                    .focused($namingSelf)
                    .submitLabel(.done)
                if let nameError {
                    Text(nameError)
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.tomato)
                        .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Bio")
                TextField("What kind of cook are you?", text: $bio, axis: .vertical)
                    .plType(.body, .medium)
                    .lineLimit(2...4)
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .plTappableField()
            }

            Text("Apple shares your name only at first sign-in, and never your photo. Set both here.")
                .plType(.micro, .medium)
                .foregroundStyle(Color.inkSecondary)

            InkPillButton(title: "Done") {
                // Only leave if it took. Dismissing regardless is how a
                // refusal became invisible.
                if saveName() {
                    savePhoto()
                    dismiss()
                }
            }
            Spacer()
        }
        .onAppear {
            let owner = members.first(where: \.isOwner)
            let name = owner?.name ?? firstName
            draftName = HouseholdIdentity.isPlaceholder(name) ? "" : name
            photoData = owner?.photoData
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self),
                   let square = ProfilePhoto.square(raw) {
                    Haptic.plate()
                    withAnimation(.plPop) { photoData = square }
                }
                pickerItem = nil
            }
        }
        .padding(.horizontal, 24)
        .presentationDetents([.height(430), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    private var draftInitials: String {
        let source = draftName.trimmingCharacters(in: .whitespaces)
        let letters = source.split(separator: " ").prefix(2)
            .compactMap { $0.first }.map(String.init).joined().uppercased()
        return letters.isEmpty ? "?" : letters
    }

    /// The photo rides on the owner's row so it syncs to the household the
    /// same way a recipe photo does. Saved after the name, because a name
    /// collision aborts the whole Done and a half-applied edit is worse than
    /// none.
    private func savePhoto() {
        guard let owner = members.first(where: \.isOwner),
              owner.photoData != photoData else { return }
        owner.photoData = photoData
        Persist.save(context)
    }

    /// The name lives in two places: the preference the app reads for
    /// authorship, and the owner's own row at the table. Both or neither.
    @discardableResult
    private func saveName() -> Bool {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        // An empty field means "I didn't touch the name" — the bio is the
        // other control on this sheet, so that has to stay a clean exit.
        guard !name.isEmpty else { return true }

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
            switch HouseholdIdentity.rename(owner, to: name, in: context) {
            case .renamed, .unchanged:
                break
            case .nameTaken(let who):
                Haptic.warn()
                withAnimation(.plSnap) {
                    nameError = "\(who) already uses that name. Try another."
                }
                return false
            case .invalid, .failed:
                Haptic.warn()
                withAnimation(.plSnap) {
                    nameError = "That didn't save. Try again."
                }
                return false
            }
        }
        nameError = nil
        firstName = name
        Haptic.plate()
        return true
    }
}

/// The settings drawer — where the light switch actually belongs. Quiet
/// controls, one card each: the room, the calendar, the subscription.
struct SettingsSheet: View {
    /// Set when Settings is opened from Home's "Your Household" title —
    /// the user asked to name the house, so put them in the field.
    var focusHouseholdName = false

    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    /// Calendar access was asked for and refused. Not persisted: it is a
    /// fact about this moment, and somebody who fixes it in Settings should
    /// find the row plain again when they come back.
    @State private var calendarRefused = false

    private var appearance: Appearance { Appearance(rawValue: appearanceRaw) ?? .system }
    @AppStorage("showCalendarEvents") private var showCalendarEvents = false
    @AppStorage("householdName") private var householdName = ""
    /// The door flag RootView reads. Signing out flips this one only.
    @AppStorage("didSignIn") private var didSignIn = false
    @State private var signOutAsked = false
    @State private var sync = SyncStatus.shared
    @AppStorage("remindersOn") private var remindersOn = true
    @State private var remindersAllowed = false
    @State private var paywallShown = false
    @State private var plusActive = PlatedPlus.isActive
    @FocusState private var namingHousehold: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Plated")
                Text("Settings")
                    .plType(.title)
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
                        caption: "What your household is called on Home."
                    ) {
                        TextField("Family name", text: $householdName)
                            .plType(.body, .bold)
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
                        icon: appearance == .dark ? "moon.stars.fill"
                            : (appearance == .light ? "sun.max" : "circle.lefthalf.filled"),
                        title: "Appearance",
                        caption: appearance == .system
                            ? "Following your phone."
                            : "Always \(appearance.label.lowercased()), whatever your phone is set to."
                    ) {
                        // A menu rather than a switch: two states could not
                        // express "follow the phone", which is the state
                        // every other app on the Home Screen is in, and the
                        // one this app's own widget has always been in.
                        // Picker carries its own VoiceOver label and value.
                        Picker("Appearance", selection: $appearanceRaw) {
                            ForEach(Appearance.allCases) { option in
                                Text(option.label).tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.ink)
                        .onChange(of: appearanceRaw) { _, _ in Haptic.select() }
                    }

                    settingRow(
                        icon: "bell",
                        title: "Cook reminders",
                        caption: remindersAllowed
                            ? "The evening before someone cooks, and Sundays when the week's still open."
                            : "Turn on notifications for Plated in iOS Settings."
                    ) {
                        // Green and on while iOS refuses to deliver is the
                        // honesty rule broken by a control: the caption
                        // underneath already said to go to Settings, and the
                        // switch above it was contradicting the caption.
                        // Permission is revoked in Settings long after the
                        // preference was set here, so the stored value alone
                        // has never been the answer.
                        Toggle("Cook reminders", isOn: Binding(
                            get: { remindersOn && remindersAllowed },
                            set: { remindersOn = $0 }
                        ))
                            .labelsHidden()
                            .tint(Color.basil)
                            .disabled(!remindersAllowed)
                            .sensoryFeedback(.selection, trigger: remindersOn)
                            .onChange(of: remindersOn) { _, on in
                                Task { if !on { await NotificationScheduler.cancelAll() } }
                            }
                    }

                    settingRow(
                        icon: "calendar",
                        title: "Calendar on the plan",
                        // A switch that answers a tap by turning itself back
                        // off, in silence, is the interface refusing without
                        // saying so. iOS only ever asks once, so the second
                        // attempt does not even raise a prompt: it just
                        // flicks back. The reminders row above already says
                        // where to go; this one says it too now.
                        caption: calendarRefused
                            ? "Plated can't see your calendar. Allow it in Settings, Privacy, Calendars."
                            : "Show Apple Calendar events next to each night."
                    ) {
                        Toggle("Calendar on the plan", isOn: $showCalendarEvents)
                            .labelsHidden()
                            .sensoryFeedback(.selection, trigger: showCalendarEvents)
                            .tint(Color.basil)
                            .onChange(of: showCalendarEvents) { _, on in
                                guard on else {
                                    calendarRefused = false
                                    return
                                }
                                Task {
                                    let granted = await DayEventsProvider.shared.requestAccess()
                                    if !granted {
                                        withAnimation(.plSnap) {
                                            showCalendarEvents = false
                                            calendarRefused = true
                                        }
                                        Haptic.warn()
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
                                caption: plusActive ? "Active. Unlimited household members." : "Add your whole household."
                            ) {
                                Text(plusActive ? "ACTIVE" : "JOIN")
                                    .plType(.micro, .extraBold)
                                    .foregroundStyle(plusActive ? Color.basil : Color.tomato)
                            }
                        }
                        .buttonStyle(.pressable)
                    }

                    // Where someone who suspects something is wrong comes
                    // to look. Silent when everything is fine — an always-on
                    // "synced" badge is chrome bragging.
                    if let line = sync.account.line {
                        settingRow(
                            icon: "icloud.slash",
                            title: "Not syncing",
                            caption: line
                        ) { EmptyView() }
                    }

                    if sync.saveFailed {
                        Button {
                            Haptic.tap()
                            sync.acknowledgeSaveFailure()
                        } label: {
                            settingRow(
                                icon: "exclamationmark.triangle",
                                title: "Something didn't save",
                                caption: "A recent change didn't save. It's still on screen, so try it once more."
                            ) {
                                Text("DISMISS")
                                    .plType(.micro, .extraBold)
                                    .foregroundStyle(Color.tomato)
                            }
                        }
                        .buttonStyle(.pressable)
                    }

                    Button {
                        Haptic.tap()
                        signOutAsked = true
                    } label: {
                        settingRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            title: "Sign out",
                            caption: "Ends this Apple sign-in. Nothing is deleted."
                        ) {
                            Text("SIGN OUT")
                                .plType(.micro, .extraBold)
                                .foregroundStyle(Color.tomato)
                        }
                    }
                    .buttonStyle(.pressable)

                    Text(Self.versionLine)
                        .plType(.micro, .medium)
                        .foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        // A sheet does not inherit the root's preferredColorScheme, so
        // changing the appearance from the control inside this very sheet
        // repainted the whole app behind it and left the sheet in the old
        // room until it was dismissed. Which is the only moment this can
        // happen, since this is where the control lives.
        .preferredColorScheme(appearance.scheme)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .onAppear {
            if focusHouseholdName { namingHousehold = true }
        }
        .task {
            await sync.refresh()
            remindersAllowed = await NotificationScheduler.authorized()
        }
        .sheet(isPresented: $paywallShown, onDismiss: { plusActive = PlatedPlus.isActive }) {
            PaywallSheet()
        }
        .confirmationDialog(
            "Sign out of Plated?", isPresented: $signOutAsked, titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) { signOut() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("Nothing is deleted. Your recipes, your week and your household stay where they are.")
        }
    }

    /// The same scope RootView documents for a revoked credential: clear the
    /// Keychain identity and the door flag, leave the table alone. Nothing
    /// here deletes a recipe, a week or a member.
    ///
    /// `didSetTable` deliberately survives. Signing out is not starting
    /// over — the table is already set, the household already exists, and
    /// making someone re-pick their people every time they sign back in
    /// would punish them for using the door. Sign in returns you straight
    /// to your week.
    private func signOut() {
        AppleIdentity.clear()
        Haptic.plate()
        dismiss()
        // Let the sheet finish leaving before the root swaps underneath it.
        // Flipping the door flag while this sheet is still up strands it on
        // a view that no longer exists.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            didSignIn = false
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
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                Text(caption)
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))
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
                    .plType(.display)
                    .foregroundStyle(Color.ink)
                Text("Your seat is free. Plated+ adds everyone else.")
                    .plType(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .padding(.top, 30)
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 12) {
                perk("person.2", "Unlimited household seats", "Partners, kids, grandma. Everyone gets a color.")
                perk("calendar", "The whole plan, shared", "Everyone sees the week and their nights.")
                perk("bubble.left.and.bubble.right", "Comments and polls", "Ask the Table, run a poll, reply on any dish.")
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
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                    }
                    .frame(minHeight: 56)
                } else {
                    TomatoPillButton(title: "Start Plated+ · $2.99/mo",
                                     haptic: Haptic.kiss) {
                        PlatedPlus.isActive = true
                        withAnimation(.plPop) { active = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            dismiss()
                        }
                    }
                    Text("Preview only. No payment is taken.")
                        .plType(.micro, .medium)
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        // The buy button was the last thing in a VStack that does not
        // scroll, so above about AX1 it was off the bottom of the sheet with
        // nothing to drag.
        .plFitsOrScrolls()
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
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                Text(caption)
                    .plType(.caption)
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

private extension SettingsSheet {
    /// Read, not typed. `scripts/testflight.sh` bumps only CURRENT_PROJECT_VERSION,
    /// so a literal here reported the same string for every build ever uploaded
    /// and the one question this line exists to answer ("which build am I on?")
    /// had no answer.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Plated \(short) (\(build))"
    }
}
