import SwiftUI
import UserNotifications
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
    private var storedPosts: [TablePost]
    private var allPosts: [TablePost] { storedPosts.filter(\.isUserContent) }
    @Query private var recipes: [Recipe]
    @Query(sort: \PlannedMeal.date) private var plannedMeals: [PlannedMeal]
    // Oldest first: two devices racing a first banner before sync merges
    // both insert a row, and an unsorted `.first` flips arbitrarily between
    // them per device. The oldest row is the household's one true profile.
    @Query(sort: \HouseholdProfile.createdAt) private var profiles: [HouseholdProfile]

    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("userBio") private var myBio = ""
    @AppStorage("userFamilyName") private var userFamilyName = ""
    @State private var settingsShown = false
    @State private var editShown = false
    @State private var householdShown = false
    @State private var profileTab = "Dishes"
    @State private var savedRecipe: Recipe?
    @State private var bannerItem: PhotosPickerItem?
    @State private var openedPost: TablePost?
    @State private var awardsShown = false
    @State private var awards: [PlatedAward] = []
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
        case .left:
            return "\(firstName) left the household."
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

    private var isMe: Bool { member?.isMe ?? false }

    /// The line a person wrote about themselves. It belongs to the seat
    /// they are (docs/household.md §3.1), so it travels and everyone's page
    /// can show it. `myBio` stays only as the reader's own fallback: a
    /// phone with no seat row yet, and the bios written before the line
    /// reached the row at all.
    private var bioLine: String {
        let seated = (member?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !seated.isEmpty { return seated }
        return isMe ? myBio.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

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
                                .plType(.display)
                                .foregroundStyle(Color.ink)
                        }
                        MicroLabel(roleLine)
                        if !bioLine.isEmpty {
                            Text(bioLine)
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
                            count: typeSize >= .accessibility1 ? 2 : 3
                        ),
                        spacing: typeSize >= .accessibility1 ? 16 : 0
                    ) {
                        CountBlock(value: "\(posts.count)", label: "Posts")
                        CountBlock(value: "\(plateCount)", label: "Happy plates")
                        CountBlock(value: "\(kissCount)", label: "Chef's kisses", accent: kissCount > 0)
                    }
                    .padding(.vertical, 12)

                    AwardsHighlightShelf(awards: awards, showsProgress: isMe) {
                        awardsShown = true
                    }
                }
                .padding(.horizontal, 24)

                HStack(spacing: 0) {
                    ForEach(isMe ? ["Dishes", "Conversations", "Saved"] : ["Dishes", "Conversations"], id: \.self) { tab in
                        Button { Haptic.select(); withAnimation(.plSnap) { profileTab = tab } } label: {
                            Text(tab)
                                .plType(.footnote, profileTab == tab ? .semibold : .regular)
                                .plActionLabel(0.7)
                                .foregroundStyle(profileTab == tab ? Color.accentText : Color.inkSecondary)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .overlay(alignment: .bottom) { Rectangle().fill(profileTab == tab ? Color.tomato : Color.hairline).frame(height: profileTab == tab ? 2 : 0.5) }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityAddTraits(profileTab == tab ? .isSelected : [])
                    }
                }.padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 16)
                if profileTab == "Saved", isMe {
                    let saved = recipes.filter { $0.isImported }
                    if saved.isEmpty {
                        profileEmpty("Your recipe shelf", detail: "Recipes you save from the Table appear here. Your household can see them too.")
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                            ForEach(saved) { recipe in
                                Button { savedRecipe = recipe } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        RecipeArtwork(data: recipe.photoData, title: recipe.title, ratio: 1)
                                        Text(recipe.title).plType(.body, .semibold).foregroundStyle(Color.ink)
                                    }
                                }.buttonStyle(.pressable)
                            }
                        }.padding(.horizontal, 24)
                    }
                } else if profileTab == "Conversations" {
                    let conversations = posts.filter { $0.kind == "ask" }
                    if conversations.isEmpty {
                        profileEmpty("A place for good conversation", detail: "Questions and polls shared with the Table appear here.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(conversations) { post in
                                Button { openedPost = post } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(post.dishTitle.isEmpty ? post.caption : post.dishTitle).plType(.heading, .semibold).foregroundStyle(Color.ink)
                                        Text(post.createdAt.formatted(.dateTime.month(.abbreviated).day())).plType(.caption).foregroundStyle(Color.inkSecondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 18).contentShape(Rectangle())
                                }.buttonStyle(.pressable)
                                Divider()
                            }
                        }.padding(.horizontal, 24)
                    }
                } else {
                    let dishes = posts.filter { $0.kind != "ask" }
                    if dishes.isEmpty { profileEmpty("Nothing plated yet", detail: emptyLine) }
                    else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                            ForEach(dishes, id: \.persistentModelID) { post in postCell(post) }
                        }
                    }
                }
            }
            .padding(.bottom, Layout.floatingChromeInset)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .plSwipeBack()
        .safeAreaInset(edge: .top) { topBar }
        .sheet(isPresented: Binding(get: { settingsShown || editShown || householdShown || awardsShown }, set: { if !$0 { settingsShown = false; editShown = false; householdShown = false; awardsShown = false } })) {
            if awardsShown {
                NavigationStack {
                    AwardsGalleryView(personName: displayName, awards: awards, showsProgress: isMe)
                }
            }
            else if settingsShown { SettingsSheet() }
            else if editShown { EditProfileSheet() }
            else {
                HouseholdHomeView()
                    .safeAreaInset(edge: .top) {
                        HStack { Text("Your household").plType(.heading); Spacer(); DesignIconButton(symbol: "xmark", label: "Close household") { householdShown = false } }.padding(.horizontal, 24).background(Color.canvas)
                    }
            }
        }
        .navigationDestination(item: $savedRecipe) { recipe in RecipeDetailView(recipe: recipe) }
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
        .task(id: awardActivitySignature) { refreshAwards() }
    }

    private func profileEmpty(_ title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: profileTab == "Saved" ? "bookmark" : "bubble.left.and.bubble.right").font(.system(size: 26, weight: .light)).foregroundStyle(Color.inkSecondary)
            Text(title).plType(.heading, .semibold).foregroundStyle(Color.ink)
            Text(detail).plType(.footnote).foregroundStyle(Color.inkSecondary).multilineTextAlignment(.center)
        }.padding(.horizontal, 32).padding(.vertical, 36).frame(maxWidth: .infinity)
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
                        Image(systemName: "arrow.left")
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
                DesignIconButton(symbol: "house", label: "Your household") { householdShown = true }
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
                .plActionLabel()
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

    /// The person's role, and "Head of table" only for the row that holds
    /// it. This used to print "Head of table" for whoever was reading,
    /// which on a member's phone is a partner reading their own page.
    private var roleLine: String {
        if let member { return member.roleTitle }
        return "At your table"
    }

    private var awardActivitySignature: String {
        let cooked = plannedMeals.filter { $0.cookedAt != nil }.count
        let authored = allPosts.filter { $0.firstName == firstName }
        let plates = authored.reduce(0) { $0 + $1.totalPlates }
        return "\(plannedMeals.count).\(cooked).\(recipes.count).\(authored.count).\(plates).\(members.count).\(name)"
    }

    private func refreshAwards() {
        let metrics = Awards.metrics(
            for: member,
            meals: plannedMeals,
            recipes: recipes,
            posts: allPosts,
            householdSize: members.count,
            ownerFallback: isMe
        )
        awards = Awards.evaluate(metrics, for: name)
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
    @State private var draftBio = ""
    @State private var saved = false
    private var draftKey: String {
        "profile.editDraft." + (members.me.map { String(describing: $0.persistentModelID) } ?? "local")
    }
    @State private var photoData: Data?
    @State private var pickerItem: PhotosPickerItem?
    /// Why the last Done didn't take. A refusal that only buzzes is a
    /// refusal the user can't act on.
    @State private var nameError: String?
    @FocusState private var namingSelf: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Text("Edit profile")
                    // .title at 22, like Settings one sheet away.
                    .plType(.title)
                    .foregroundStyle(Color.ink)
                HStack {
                    Button("Cancel") { dismiss() }
                        .plType(.footnote, .bold)
                        .foregroundStyle(Color.ink)
                        .frame(minWidth: 44, minHeight: 44)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)

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

            Button {
                ContactPhotoPicker.choose { selected in
                    guard let selected else { return }
                    photoData = selected
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Use my contact photo").plType(.footnote, .bold)
                        .plActionLabel(0.72)
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(Capsule().strokeBorder(Color.hairline))
                .contentShape(Capsule())
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
                TextField("What kind of cook are you?", text: $draftBio, axis: .vertical)
                    .plType(.body, .medium)
                    .lineLimit(2...4)
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .plTappableField()
            }

            Text("Your photo helps people at your Table recognize you. Apple does not provide your account photo to Plated.")
                .plType(.micro, .medium)
                .foregroundStyle(Color.inkSecondary)

            InkPillButton(title: "Save profile") {
                // Only leave if it took. Dismissing regardless is how a
                // refusal became invisible.
                if saveName() {
                    savePhoto()
                    saveBio()
                    saved = true
                    UserDefaults.standard.removeObject(forKey: draftKey)
                    dismiss()
                }
            }
            Spacer()
        }
        .onAppear {
            let owner = members.me
            let name = owner?.name ?? firstName
            draftName = HouseholdIdentity.isPlaceholder(name) ? "" : name
            photoData = owner?.photoData
            // The row is the bio's home, so the sheet opens on it. The
            // stored value only seeds a row that has never carried one.
            draftBio = (owner?.bio).flatMap { $0.isEmpty ? nil : $0 } ?? bio
            if let kept = UserDefaults.standard.dictionary(forKey: draftKey) {
                draftName = kept["name"] as? String ?? draftName
                draftBio = kept["bio"] as? String ?? draftBio
                photoData = kept["photo"] as? Data
            }
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
        .onDisappear {
            guard !saved else { return }
            var kept: [String: Any] = ["name": draftName, "bio": draftBio]
            kept["photo"] = photoData
            UserDefaults.standard.set(kept, forKey: draftKey)
        }
        .padding(.horizontal, 24)
        .plFitsOrScrolls()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .plTapOutsideToDismiss()
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
        guard let owner = members.me,
              owner.photoData != photoData else { return }
        owner.photoData = photoData
        Persist.save(context)
    }

    /// The bio rides on the seat too. It used to be written only to
    /// `userBio`, so `HouseholdMember.bio` was always "" on the wire and a
    /// partner's page on the host's phone never showed the line they had
    /// written about themselves. The preference is kept in step because
    /// it is what a phone with no seat row still reads.
    private func saveBio() {
        let trimmed = draftBio.trimmingCharacters(in: .whitespacesAndNewlines)
        bio = trimmed
        guard let owner = members.me, owner.bio != trimmed else { return }
        owner.bio = trimmed
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
        if let owner = members.me {
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
                perk("calendar", "The whole plan, shared", "Everyone in the household sees the week and their nights.")
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
