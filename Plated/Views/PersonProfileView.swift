import SwiftUI
import UserNotifications
import SwiftData
import PhotosUI

/// A person at the table. Identity and what they have shared live here;
/// household management and app preferences are pushed destinations rather
/// than a stack of account sheets.
struct PersonProfileView: View {
    let personName: String
    let colorHex: String
    var memberID: PersistentIdentifier?

    var body: some View {
        ProfileDestination(personName: personName, colorHex: colorHex, memberID: memberID)
            .equatable()
    }
}

/// Navigation can recreate a destination while reconciling another push or
/// sheet. Comparing only routing inputs prevents fresh Query wrappers from
/// feeding that reconciliation back into itself. Live data and environment
/// subscriptions stay in the content, below this identity boundary.
private struct ProfileDestination: View, Equatable {
    let personName: String
    let colorHex: String
    var memberID: PersistentIdentifier?

    var body: some View {
        PersonProfileContent(personName: personName, colorHex: colorHex, memberID: memberID)
    }
}

private struct PersonProfileContent: View {
    /// The name this page was pushed with. Read `name` instead of this
    /// anywhere the answer must stay current — see below.
    let personName: String
    let colorHex: String
    /// Identity, when the person is a seat here. A page keyed only on a
    /// name string goes stale the moment that name changes underneath it:
    /// the title reverts to "Me", the gear disappears, and "Edit profile"
    /// turns into "Message" pointing at a DM thread with yourself.
    var memberID: PersistentIdentifier?

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    // A roster refresh can delete a seat while this pushed page still
    // holds the previous query snapshot.
    private var roster: [HouseholdMember] { members.readable }
    // An author is the one thing every real post has. The empty-name
    // rows are blanks the CloudKit mirror adopts (TablePost.isBlank),
    // and counting them puts a dish on the board nobody cooked.
    @Query(filter: #Predicate<TablePost> { !$0.isDiscover && !$0.authorName.isEmpty }, sort: \TablePost.createdAt, order: .reverse)
    private var storedPosts: [TablePost]
    private var allPosts: [TablePost] {
        storedPosts.filter {
            $0.isUserContent
                && !contentSafety.isBlocked(authorID: $0.authorID, authorName: $0.authorName)
        }
    }
    @Query private var recipes: [Recipe]
    @Query(sort: \PlannedMeal.date) private var plannedMeals: [PlannedMeal]
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("userBio") private var myBio = ""
    @AppStorage("userFirstName") private var userFirstName = ""
    @AppStorage("userFamilyName") private var userFamilyName = ""
    @AppStorage("userProfileBannerPhotoData") private var localProfileBannerPhoto = Data()
    @AppStorage("householdName") private var householdName = ""
    @State private var settingsShown = false
    @State private var editShown = false
    @State private var householdShown = false
    @State private var profileTab = "Dishes"
    @State private var savedRecipe: Recipe?
    @State private var openedPost: TablePost?
    @State private var awardsShown = false
    @State private var awards: [PlatedAward] = []
    @State private var contentSafety = ContentSafety.shared
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
        if isMe { return "Dinner wins, weeknight experiments and favorite plates will collect here." }
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
        if let memberID, let seated = roster.first(where: { $0.persistentModelID == memberID }) {
            return seated
        }
        // Guests at the table have no seat to match — fall back to the name.
        let pushedFirst = personName.split(separator: " ").first.map(String.init) ?? personName
        return roster.first { $0.name == personName || $0.name == pushedFirst }
    }

    private var isMe: Bool {
        if let member { return member.isMe }
        let pushed = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        return HouseholdIdentity.isPlaceholder(pushed)
            || (!userFirstName.isEmpty && pushed == userFirstName)
    }

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
        allPosts.filter { $0.authorName == name || $0.firstName == firstName }
    }

    private var dishes: [TablePost] { posts.filter { $0.kind != "ask" } }
    private var conversations: [TablePost] { posts.filter { $0.kind == "ask" } }

    private var kissCount: Int {
        let seats = TableKiss.seating(members: roster, dishAuthors: dishes.map(\.authorName))
        return dishes.filter { $0.hasChefsKiss(seats: seats) }.count
    }
    private var plateCount: Int { dishes.reduce(0) { $0 + $1.totalPlates } }

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
                        if let roleLine {
                            MicroLabel(roleLine)
                        }
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
                    if !dishes.isEmpty || plateCount > 0 || kissCount > 0 {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 0),
                                count: typeSize >= .accessibility1 ? 2 : 3
                            ),
                            spacing: typeSize >= .accessibility1 ? 16 : 0
                        ) {
                            CountBlock(value: "\(dishes.count)", label: "Dishes")
                            CountBlock(value: "\(plateCount)", label: "Happy plates")
                            CountBlock(value: "\(kissCount)", label: "Chef's kisses", accent: kissCount > 0)
                        }
                        .padding(.vertical, 12)
                    }

                    if isMe {
                        householdCard
                            .padding(.top, 4)
                    }

                    if awards.contains(where: { $0.current > 0 }) {
                        AwardsHighlightShelf(awards: awards, showsProgress: isMe) {
                            awardsShown = true
                        }
                    }
                }
                .padding(.horizontal, 24)

                HStack(spacing: 0) {
                    ForEach(isMe ? ["Dishes", "Questions", "Favorites"] : ["Dishes", "Questions"], id: \.self) { tab in
                        Button { Haptic.select(); withAnimation(.plSnap) { profileTab = tab } } label: {
                            Text(tab)
                                .plType(.footnote, profileTab == tab ? .semibold : .regular)
                                .plActionLabel(0.7)
                                .foregroundStyle(profileTab == tab ? Color.accentText : Color.inkSecondary)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .overlay(alignment: .bottom) { Rectangle().fill(profileTab == tab ? Color.olive : Color.hairline).frame(height: profileTab == tab ? 2 : 0.5) }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityAddTraits(profileTab == tab ? .isSelected : [])
                    }
                }.padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 16)
                if profileTab == "Favorites", isMe {
                    let favorites = recipes.filter(\.isFavorite)
                    if favorites.isEmpty {
                        profileEmpty("No favorites yet", detail: "Recipes you heart in your cookbook appear here.")
                    } else {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible()),
                                count: typeSize >= .accessibility1 ? 1 : 2
                            ),
                            spacing: 20
                        ) {
                            ForEach(favorites) { recipe in
                                Button { savedRecipe = recipe } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        RecipeArtwork(data: recipe.photoData, title: recipe.title, ratio: 1)
                                        Text(recipe.title).plType(.body, .semibold).foregroundStyle(Color.ink)
                                    }
                                }.buttonStyle(.pressable)
                            }
                        }.padding(.horizontal, 24)
                    }
                } else if profileTab == "Questions" {
                    if conversations.isEmpty {
                        profileEmpty("No questions yet", detail: isMe ? "Questions you ask at the Table will live here." : "Questions \(firstName) asks at the Table will live here.")
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
                    if dishes.isEmpty { profileEmpty(isMe ? "Your first plate starts here" : "Nothing plated yet", detail: emptyLine) }
                    else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                            ForEach(dishes, id: \.persistentModelID) { post in postCell(post) }
                        }
                    }
                }
            }
            .padding(.bottom, Layout.focusedPageBottom)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .plSwipeBack()
        .safeAreaInset(edge: .top) { topBar }
        .hidesFloatingChrome()
        // Browsing destinations push like the profile itself. Editing is the
        // only task-shaped sheet on this page.
        .navigationDestination(isPresented: $settingsShown) {
            SettingsSheet(isPushed: true)
        }
        .navigationDestination(isPresented: $awardsShown) {
            AwardsGalleryView(personName: displayName, awards: awards, showsProgress: isMe)
        }
        .navigationDestination(isPresented: $householdShown) {
            HouseholdHomeView(embedded: true)
        }
        .sheet(isPresented: $editShown) {
            EditProfileSheet()
        }
        .navigationDestination(item: $savedRecipe) { recipe in RecipeDetailView(recipe: recipe) }
        .navigationDestination(item: $openedPost) { post in
            PostThreadView(post: post)
                .navigationTransition(.zoom(sourceID: post.persistentModelID, in: zoom))
        }
        .task(id: awardActivitySignature) { refreshAwards() }
        #if DEBUG
        // Screenshot/review harness: pair with `-plated-open-profile` so a
        // review can reach the pushed Settings screen without synthesizing
        // a coordinate tap against whatever simulator size is in use.
        .onAppear {
            if isMe, LaunchFlags.consume("-plated-open-settings") {
                settingsShown = true
            }
            if isMe, LaunchFlags.consume("-plated-open-edit-profile") {
                editShown = true
            }
        }
        #endif
    }

    private func profileEmpty(_ title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: profileTab == "Favorites" ? "heart" : profileTab == "Questions" ? "bubble.left.and.bubble.right" : "fork.knife")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.inkSecondary)
            Text(title).plType(.heading, .semibold).foregroundStyle(Color.ink)
            Text(detail).plType(.footnote).foregroundStyle(Color.inkSecondary).multilineTextAlignment(.center)
        }.padding(.horizontal, 32).padding(.vertical, 36).frame(maxWidth: .infinity)
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack(spacing: 12) {
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

            Text(isMe ? "Your profile" : firstName)
                .plType(.heading, .semibold)
                .foregroundStyle(Color.ink)
                .lineLimit(1)

            Spacer(minLength: 8)
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
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    /// A profile is a person, not the household photo over Home. The old
    /// 150-point empty cover reused `HouseholdProfile.bannerPhotoData`, which
    /// made changing your personal background silently change the family's
    /// banner too. This compact, recognisable field stays personal without
    /// inventing a second photo model.
    private var banner: some View {
        Group {
            if let data = member?.profileBannerPhotoData ?? (isMe && !localProfileBannerPhoto.isEmpty ? localProfileBannerPhoto : nil),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [profileTone.tint, Color.canvas],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Circle()
                        .fill(Color.grapeTint.opacity(0.72))
                        .frame(width: 124, height: 124)
                        .blur(radius: 18)
                        .offset(x: 132, y: -44)
                    Circle()
                        .fill(Color.mangoTint.opacity(0.55))
                        .frame(width: 90, height: 90)
                        .blur(radius: 20)
                        .offset(x: -142, y: 46)
                }
            }
        }
        .frame(height: 112)
        .clipped()
        .accessibilityHidden(true)
    }

    private var profileTone: PersonTone {
        isMe ? .neutralPair : PersonTone.from(hex: colorHex)
    }

    private var householdCard: some View {
        Button {
            Haptic.select()
            householdShown = true
        } label: {
            HStack(spacing: 14) {
                householdFaces

                VStack(alignment: .leading, spacing: 3) {
                    MicroLabel("Your household")
                    Text(householdDisplayName)
                        .plName()
                        .plType(.body, .bold)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text("Plan, shop and cook together")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(Color.raisedFill, in: Radius.shape(Radius.card))
            .overlay(Radius.shape(Radius.card).strokeBorder(Color.hairline))
            .contentShape(Radius.shape(Radius.card))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Your household, \(householdDisplayName)")
        .accessibilityHint("Shows people, invitations and cook nights.")
    }

    private var householdFaces: some View {
        let people = Array(roster.listed.prefix(3))
        return HStack(spacing: -10) {
            ForEach(people, id: \.persistentModelID) { person in
                AvatarCircle(
                    initials: person.initials,
                    tone: person.isMe ? .neutralPair : person.tone,
                    size: 38,
                    photo: person.photoData
                )
                .overlay(Circle().strokeBorder(Color.raisedFill, lineWidth: 2))
            }
            if people.isEmpty {
                Image(systemName: "house.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.completion)
                    .frame(width: 42, height: 42)
                    .background(Color.basilTint, in: Circle())
            }
        }
        .frame(minWidth: 42, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var householdDisplayName: String {
        let typed = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        let cached = HouseholdShare.cachedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cached.isEmpty { return cached }
        let ownerName = roster.first(where: \.isOwner)?.name ?? ""
        return HouseholdIdentity.displayName(
            typed: "",
            appleFamilyName: userFamilyName,
            ownerName: ownerName
        )
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
        .accessibilityLabel(
            post.dishTitle.isEmpty
                ? "Post by \(post.authorName)"
                : "\(post.dishTitle), by \(post.authorName)"
        )
        .accessibilityHint("Opens the post")
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
                .overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline, lineWidth: 1.5))
                .frame(minHeight: 44)
                .contentShape(Radius.shape(Radius.chip))
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

    /// Own page has no role. Host is only for the other person when they
    /// host this household. Partner, kid, guest, and a name with no seat
    /// get nothing: roleTitle and "At your table" are not this path's voice.
    private var roleLine: String? {
        guard !isMe, member?.isOwner == true else { return nil }
        return "Household organizer"
    }

    private var awardActivitySignature: String {
        let cooked = plannedMeals.filter { $0.cookedAt != nil }.count
        let authored = allPosts.filter { $0.firstName == firstName }
        let plates = authored.reduce(0) { $0 + $1.totalPlates }
        return "\(plannedMeals.count).\(cooked).\(recipes.count).\(authored.count).\(plates).\(roster.count).\(name)"
    }

    private func refreshAwards() {
        let metrics = Awards.metrics(
            for: member,
            meals: plannedMeals,
            recipes: recipes,
            posts: allPosts,
            householdSize: roster.count,
            kissSeats: TableKiss.seating(members: roster, dishAuthors: allPosts.map(\.authorName)),
            ownerFallback: isMe
        )
        awards = Awards.evaluate(metrics, for: name)
    }

    /// Household Home owns this image. Kept here as a shared image utility
    /// until the storage concern moves out of the view layer.
    static func writeCover(_ raw: Data, into profiles: [HouseholdProfile], context: ModelContext) {
        let processed = ProfilePhoto.downscale(raw)
        if let profile = profiles.first {
            profile.bannerPhotoData = processed
        } else {
            context.insert(HouseholdProfile(bannerPhotoData: processed))
        }
    }
}

/// Personal details and photos, kept separate from household profile media.
struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query(sort: \Recipe.createdAt) private var reviewRecipes: [Recipe]
    @AppStorage("userBio") private var bio = ""
    @AppStorage("userFirstName") private var firstName = ""
    @AppStorage("userProfileBannerPhotoData") private var localProfileBannerPhoto = Data()
    @State private var draftName = ""
    @State private var draftBio = ""
    @State private var avoidedIngredientsText = ""
    @State private var saved = false
    private var draftKey: String {
        "profile.editDraft." + (members.readable.me.map { String(describing: $0.persistentModelID) } ?? "local")
    }
    @State private var photoData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var bannerPhotoData: Data?
    @State private var bannerPickerItem: PhotosPickerItem?
    @State private var bannerCropSource: Data?
    @State private var showBannerCrop = false
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

            VStack(spacing: 8) {
                Group {
                    if let bannerPhotoData, let image = UIImage(data: bannerPhotoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [Color.inkFaint.opacity(0.16), Color.raisedFill],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color.inkSecondary)
                        }
                    }
                }
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(Radius.shape(Radius.card))
                .accessibilityHidden(true)

                HStack(spacing: 8) {
                    PhotosPicker(selection: $bannerPickerItem, matching: .images) {
                        Label(bannerPhotoData == nil ? "Add banner photo" : "Change banner photo", systemImage: "photo")
                            .plType(.footnote, .bold)
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)

                    if bannerPhotoData != nil {
                        Button {
                            Haptic.tap()
                            withAnimation(.plSnap) { bannerPhotoData = nil }
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .plType(.footnote, .semibold)
                                .foregroundStyle(Color.inkSecondary)
                                .frame(minHeight: 44)
                                .padding(.horizontal, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityHint("Removes your profile banner when you save")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if draftName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Add your name")
                        .plType(.footnote, .semibold)
                        .foregroundStyle(Color.ink)
                } else {
                    MicroLabel("Your name")
                }
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
                        .foregroundStyle(Color.dangerText)
                        .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Bio")
                TextField("A short line about you", text: $draftBio, axis: .vertical)
                    .plType(.body, .medium)
                    .lineLimit(2...4)
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .plTappableField()
            }

            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Ingredients to avoid")
                TextField("For example: peanuts, sesame", text: $avoidedIngredientsText, axis: .vertical)
                    .plType(.body, .medium)
                    .lineLimit(2...4)
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .plTappableField()
                Text("Separate with commas. Plated skips matching recipes in suggestions. This list cannot verify allergy safety, so check every recipe and package.")
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Apple doesn't share your Apple ID photo with apps.")
                .plType(.micro, .medium)
                .foregroundStyle(Color.inkSecondary)

            SecondaryActionButton(title: "Save") {
                // Only leave if it took. Dismissing regardless is how a
                // refusal became invisible.
                if saveName() {
                    savePhoto()
                    saveBannerPhoto()
                    saveBio()
                    saveFoodPreferences()
                    saved = true
                    UserDefaults.standard.removeObject(forKey: draftKey)
                    dismiss()
                }
            }
            Spacer()
        }
        .onAppear {
            let owner = members.readable.me
            let name = owner?.name ?? firstName
            draftName = HouseholdIdentity.isPlaceholder(name) ? "" : name
            photoData = owner?.photoData
            bannerPhotoData = owner?.profileBannerPhotoData
                ?? (localProfileBannerPhoto.isEmpty ? nil : localProfileBannerPhoto)
            // The row is the bio's home, so the sheet opens on it. The
            // stored value only seeds a row that has never carried one.
            draftBio = (owner?.bio).flatMap { $0.isEmpty ? nil : $0 } ?? bio
            avoidedIngredientsText = (owner?.avoidedIngredients ?? []).joined(separator: ", ")
            if let kept = UserDefaults.standard.dictionary(forKey: draftKey) {
                draftName = kept["name"] as? String ?? draftName
                draftBio = kept["bio"] as? String ?? draftBio
                avoidedIngredientsText = kept["avoidedIngredients"] as? String ?? avoidedIngredientsText
                photoData = kept["photo"] as? Data
                if kept["bannerPhotoWasSet"] as? Bool == true {
                    bannerPhotoData = kept["bannerPhoto"] as? Data
                }
            }
            #if DEBUG
            if LaunchFlags.consume("-plated-review-banner-crop"),
               let photo = reviewRecipes.compactMap(\.photoData).first,
               let framed = BannerFocus.framed(photo) {
                bannerCropSource = framed
                showBannerCrop = true
            }
            #endif
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
        .onChange(of: bannerPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self),
                   let framed = BannerFocus.framed(raw) {
                    Haptic.plate()
                    bannerCropSource = framed
                    showBannerCrop = true
                }
                bannerPickerItem = nil
            }
        }
        .sheet(isPresented: $showBannerCrop) {
            if let bannerCropSource {
                BannerCropSheet(data: bannerCropSource) { adjusted in
                    withAnimation(.plSnap) { bannerPhotoData = adjusted }
                    showBannerCrop = false
                }
            }
        }
        .onDisappear {
            guard !saved else { return }
            var kept: [String: Any] = [
                "name": draftName,
                "bio": draftBio,
                "avoidedIngredients": avoidedIngredientsText
            ]
            kept["photo"] = photoData
            kept["bannerPhoto"] = bannerPhotoData
            kept["bannerPhotoWasSet"] = true
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
        guard let owner = members.readable.me,
              owner.photoData != photoData else { return }
        owner.photoData = photoData
        Persist.save(context)
    }

    private func saveBannerPhoto() {
        guard let owner = members.readable.me else {
            localProfileBannerPhoto = bannerPhotoData ?? Data()
            return
        }
        localProfileBannerPhoto = Data()
        guard owner.profileBannerPhotoData != bannerPhotoData else { return }
        owner.profileBannerPhotoData = bannerPhotoData
        owner.profileBannerPhotoModifiedAt = .now
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
        guard let owner = members.readable.me, owner.bio != trimmed else { return }
        owner.bio = trimmed
        Persist.save(context)
    }

    private func saveFoodPreferences() {
        guard let owner = members.readable.me else { return }
        var seen = Set<String>()
        let values = avoidedIngredientsText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        guard owner.avoidedIngredients != values else { return }
        owner.avoidedIngredients = values
        Persist.save(context, "save avoided ingredients")
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
        if let owner = members.readable.me {
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

/// The automatic face-aware crop is a good first guess, not a final answer.
/// Let the person drag and pinch before committing the saved banner.
private struct BannerCropSheet: View {
    let data: Data
    let onSave: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var savedZoom: CGFloat = 1
    @State private var viewportSize: CGSize = .zero

    private let aspect: CGFloat = 16.0 / 9.0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button("Cancel") { dismiss() }
                    .plType(.footnote, .bold)
                    .foregroundStyle(Color.ink)
                Spacer()
                Text("Frame your banner")
                    .plType(.title)
                    .foregroundStyle(Color.ink)
                Spacer()
                Button("Save") {
                    guard let adjusted = BannerFocus.adjusted(
                        data,
                        center: normalizedCenter,
                        zoom: zoom
                    ) else { return }
                    onSave(adjusted)
                }
                .plType(.footnote, .bold)
                .foregroundStyle(Color.ink)
                .disabled(UIImage(data: data) == nil)
            }
            .frame(minHeight: 44)

            Text("Drag to reposition, pinch to zoom")
                .plType(.caption)
                .foregroundStyle(Color.inkSecondary)

            GeometryReader { geometry in
                let height = geometry.size.width / aspect
                ZStack {
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: height)
                            .scaleEffect(zoom)
                            .offset(offset)
                            .clipped()
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = clamped(
                                            CGSize(width: dragStart.width + value.translation.width,
                                                   height: dragStart.height + value.translation.height),
                                            size: CGSize(width: geometry.size.width, height: height),
                                            zoom: zoom
                                        )
                                    }
                                    .onEnded { _ in dragStart = offset }
                            )
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        zoom = min(max(savedZoom * value, 1), 2.6)
                                        offset = clamped(offset,
                                            size: CGSize(width: geometry.size.width, height: height),
                                            zoom: zoom)
                                    }
                                    .onEnded { _ in savedZoom = zoom }
                            )
                    }
                }
                .frame(width: geometry.size.width, height: height)
                .clipShape(Radius.shape(Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.hairline))
                .frame(maxHeight: .infinity, alignment: .top)
                .onAppear { viewportSize = CGSize(width: geometry.size.width, height: height) }
                .onChange(of: geometry.size) { _, size in
                    viewportSize = CGSize(width: size.width, height: size.width / aspect)
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .accessibilityLabel("Banner crop preview")

            Button("Reset framing") {
                withAnimation(.plSnap) {
                    zoom = 1
                    savedZoom = 1
                    offset = .zero
                    dragStart = .zero
                }
            }
            .plType(.footnote, .semibold)
            .foregroundStyle(Color.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(Color.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    private var normalizedCenter: CGPoint {
        // The crop view and source use the same 16:9 ratio, so displacement
        // maps directly to a normalized point in the saved source image.
        CGPoint(x: 0.5 - offset.width / max(1, zoom * viewportSize.width),
                y: 0.5 - offset.height / max(1, zoom * viewportSize.height))
    }

    private func clamped(_ proposed: CGSize, size: CGSize, zoom: CGFloat) -> CGSize {
        CGSize(
            width: min(max(proposed.width, -size.width * (zoom - 1) / 2), size.width * (zoom - 1) / 2),
            height: min(max(proposed.height, -size.height * (zoom - 1) / 2), size.height * (zoom - 1) / 2)
        )
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
                    PrimaryActionButton(title: "Start Plated+ · $2.99/mo",
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
