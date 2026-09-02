import SwiftUI
import SwiftData

/// The Table — the private feed. Reactions are plates; ten plates and the
/// dish earns its chef's kiss. Split like a good timeline: Everyone at
/// your table, or just the household. Posts open into pages, names open
/// into profiles, and saving a dish lets you make it yours first.
struct TableFeedView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<TablePost> { !$0.isDiscover },
        sort: \TablePost.createdAt, order: .reverse
    ) private var posts: [TablePost]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var recipes: [Recipe]
    @Environment(\.dynamicTypeSize) private var typeSize

    enum FeedScope: String, CaseIterable {
        case everyone = "Everyone"
        case household = "Household"
    }

    @State private var scope: FeedScope = .everyone
    @Namespace private var scopePill
    @State private var bouncePost: PersistentIdentifier?
    @State private var threadPost: TablePost?
    @State private var personShown: PersonRef?
    @State private var seatsPresented = false
    /// The composer, opened straight from the empty state. The + in the tab
    /// bar owns the same sheet, but an empty screen that can only be
    /// answered by a control somewhere else is a dead end.
    @State private var composerShown = false
    @State private var editingSave: TablePost?
    @State private var savedToast: String?
    @State private var toastToken = 0
    @State private var discoverPresented = false
    @State private var activityShown = false
    /// Long-press on a post. Feed cards aren't swipeable — a plate is a tap
    /// and the photo is a door — so the menu carries the rest.
    @State private var pendingDelete: TablePost?
    @AppStorage("pendingSeats") private var pendingSeatsRaw = ""

    /// Everything worth showing. A post with no author, no dish, no words
    /// and no photo is not a post — see `TablePost.isBlank`. Filtered here
    /// rather than in the `@Query` so the rule is stated once and every
    /// reader of the feed gets it, counts included.
    private var realPosts: [TablePost] { posts.filter { !$0.isBlank } }

    private var seatCount: Int {
        // "Sam Meadows" the author is "Sam" the household member — first
        // names bridge the two worlds until real user IDs exist.
        let knownNames = Set(members.map(\.name))
        let guests = Set(
            realPosts.filter { $0.kind == "dish" }
                .map(\.authorName)
                .filter { !knownNames.contains($0) && !knownNames.contains(String($0.split(separator: " ").first ?? "")) }
        )
        // Members already include everyone invited or joined — the old sum
        // double-counted pending ghosts while omitting people who had
        // actually accepted.
        return max(members.count + guests.count, 1)
    }

    /// Pull to refresh. `@Query` is live, so anything CloudKit has already
    /// delivered is on screen before the user pulls — "already" being the
    /// operative word. So the gesture pushes this device's own pending work
    /// out, then waits on the mirror — see CloudSync for the two deadlines,
    /// why one wasn't enough, and what it can and cannot observe. A feed
    /// you can't pull reads as stuck even when it's current, but a pull
    /// that only pretends is worse than none.
    /// Why only here, and not on the week or on Home: this is the one
    /// surface showing OTHER households' content, so it is the only one
    /// where "there might be something new on a server" is a true thought.
    /// The week and Home are this device's own data — a pull there would
    /// have no mirror to wait on. The asymmetry is deliberate; please
    /// don't tidy it into symmetry.
    private func refreshFeed() async {
        Persist.save(context)
        // Two different pipes, pulled together because the user pulled once.
        // The mirror carries this household's own devices; TableShare
        // carries everybody else's table. Neither knows about the other.
        async let remote = TableShare.fetchRemote()
        let outcome = await CloudSync.waitForImport()
        TableShare.merge(await remote, into: context)
        // Let go mid-pull and there is nothing to confirm — the tick used
        // to fire anyway, because `try?` around the sleep swallowed the
        // cancellation and left the call site unable to tell an abandoned
        // refresh from a finished one.
        guard !Task.isCancelled else { return }
        switch outcome {
        case .arrived, .quiet: Haptic.tap()
        case .failed: Haptic.warn()
        }
    }

    /// The people you granted and invited when you set your table.
    ///
    /// An invite is not an account, so these people have no posts — which
    /// meant "Everyone" quietly showed everyone who had *posted*, and the
    /// contacts you had just handed over appeared nowhere. Same storage the
    /// seats sheet reads, so cancelling an invite there empties it here.
    private var invitedSeats: [String] {
        pendingSeatsRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
            .filter { $0.first?.isLetter == true }
            .prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    /// Faces before posts: who is at the table reads ahead of what they
    /// cooked. Neutral tone, matching the seats sheet — an invited person
    /// has not earned a color yet.
    private var invitedStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel("You invited")
                .padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(invitedSeats, id: \.self) { name in
                        Button {
                            Haptic.tap()
                            seatsPresented = true
                        } label: {
                            VStack(spacing: 6) {
                                AvatarCircle(
                                    initials: initials(for: name),
                                    tone: .neutralPair, size: 48,
                                    photo: members.photo(forAuthor: name)
                                )
                                Text(name.split(separator: " ").first.map(String.init) ?? name)
                                    .font(.jakarta(11, .semibold))
                                    .foregroundStyle(Color.inkSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 62)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("\(name), invited")
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 14)
    }

    private var shownPosts: [TablePost] {
        guard scope == .household else { return realPosts }
        let names = Set(members.map(\.name))
        return realPosts.filter { names.contains($0.firstName) || names.contains($0.authorName) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                // Search sits beside the scope, the way it does on Recipes:
                // scoping the feed and searching it are the same kind of act,
                // and the header has a host to seat instead.
                HStack(spacing: 8) {
                    scopePicker
                    Button {
                        Haptic.tap()
                        discoverPresented = true
                    } label: {
                        Circle()
                            .strokeBorder(Color.hairline, lineWidth: 1.5)
                            .frame(width: 38, height: 38)
                            .overlay {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.ink)
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Discover")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                Divider().overlay(Color.hairlineSoft)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if scope == .everyone, !invitedSeats.isEmpty {
                            invitedStrip
                            Divider().overlay(Color.hairlineSoft)
                        }
                        ForEach(shownPosts, id: \.persistentModelID) { post in
                            if post.kind == "ask" {
                                askCard(post)
                            } else {
                                postCard(post)
                            }
                            Divider().overlay(Color.hairlineSoft)
                        }
                        if shownPosts.isEmpty {
                            VStack(spacing: 10) {
                                PlateReactionGlyph(filled: false)
                                Text(scope == .household ? "Your household hasn't posted yet" : "Nothing plated yet")
                                    .font(.jakarta(15, .bold))
                                    .foregroundStyle(Color.ink)
                                Text("Only the people you invite can see it.")
                                    .font(.jakarta(13, .medium))
                                    .foregroundStyle(Color.inkSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 40)
                                Button {
                                    Haptic.tap()
                                    composerShown = true
                                } label: {
                                    Text("Post a dish")
                                        .font(.jakarta(14, .bold))
                                        .foregroundStyle(Color.onTomato)
                                        .padding(.horizontal, 24)
                                        .frame(minHeight: 44)
                                        .background(Color.tomato, in: Capsule())
                                }
                                .buttonStyle(.pressable)
                                .padding(.top, 4)
                            }
                            .padding(.top, 60)
                        }
                    }
                    .padding(.bottom, Layout.floatingChromeInset)
                }
                .refreshable { await refreshFeed() }
                // A seat accepted from Messages while the Table is already
                // open would otherwise sit invisible until the next pull.
                .onReceive(NotificationCenter.default.publisher(for: ShareAcceptor.didAccept)) { _ in
                    Task { TableShare.merge(await TableShare.fetchRemote(), into: context) }
                }
            }
            .background(Color.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .plSwipeBack()
            .sheet(isPresented: $composerShown) { TableComposerSheet() }
            .navigationDestination(item: $threadPost) { post in
                PostThreadView(post: post) { beginSave($0) }
            }
            .navigationDestination(item: $personShown) { person in
                PersonProfileView(personName: person.name, colorHex: person.colorHex, memberID: person.memberID)
            }
            .navigationDestination(isPresented: $activityShown) {
                NotificationsView()
            }
            // Discover reads as a pushed screen — it wears the back chevron —
            // so it is one, and it inherits the edge swipe with the rest.
            .navigationDestination(isPresented: $discoverPresented) {
                DiscoverView()
            }
        }
        .sheet(isPresented: $seatsPresented) {
            TableSeatsSheet()
        }
        .confirmationDialog(
            "Delete this post?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let post = pendingDelete {
                Button("Delete", role: .destructive) { deletePost(post) }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("The photo and comments go too.")
        }
        .sheet(item: $editingSave) { post in
            RecipeEditorView(prefill: (
                title: post.dishTitle.isEmpty ? "\(post.firstName)'s dish" : post.dishTitle,
                summary: post.caption,
                photo: post.photoData,
                originID: post.originKey
            )) { _ in
                finishSave(post)
            }
        }
        .onAppear {
            #if DEBUG
            if LaunchFlags.consume("-plated-open-discover") {
                discoverPresented = true
            }
            if LaunchFlags.consume("-plated-open-seats") {
                seatsPresented = true
            }
            if LaunchFlags.consume("-plated-open-thread") {
                threadPost = realPosts.first { $0.kind == "dish" }
            }
            #endif
        }
        .overlay(alignment: .bottom) {
            if let toast = savedToast {
                Text(toast)
                    .font(.jakarta(13, .bold))
                    .foregroundStyle(Color.canvas)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .background(Color.ink, in: Capsule())
                    // The perch occupies 84…134; a hand-typed 100 put a long
                    // toast underneath it. The last bottom inset on the
                    // branch that hadn't gone through the token family the
                    // rest of this class was built to fix.
                    .padding(.bottom, Layout.floatingChromeInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Header

    /// Past this the title and three trailing controls cannot share a line
    /// — measured at AX3 the title broke mid-word ("The / Tabl / e"), HOST
    /// wrapped to "HO / ST", and the seat chip collapsed to "…". Home's
    /// masthead grew this same fallback on this branch; the Table has three
    /// trailing controls to Home's three and needed it just as much.
    private var hugeType: Bool { typeSize >= .accessibility1 }

    @ViewBuilder
    private var header: some View {
        if hugeType {
            VStack(alignment: .leading, spacing: 12) {
                headerTitle
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    headerControls
                }
            }
        } else {
            HStack(spacing: 12) {
                headerTitle
                Spacer(minLength: 8)
                headerControls
            }
        }
    }

    private var headerTitle: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.inkFaint)
                    MicroLabel("\(seatCount) \(seatCount == 1 ? "person" : "people") · Invite only")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text("The Table")
                    .font(.gabarito(25, .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.ink)
                    // One line at ordinary sizes; only huge type may wrap,
                    // and never mid-word.
                    .lineLimit(hugeType ? 2 : 1)
                    .minimumScaleFactor(hugeType ? 1 : 0.8)
                    .fixedSize(horizontal: false, vertical: hugeType)
            }
            .layoutPriority(1)
    }

    @ViewBuilder
    private var headerControls: some View {
            ActivityBellButton {
                activityShown = true
            }
            // The seats at your table — tap to see, message, and manage them.
            Button {
                Haptic.tap()
                seatsPresented = true
            } label: {
                HStack(spacing: -8) {
                    // The "+N" chip was drawn unconditionally with a
                    // `max(..., 1)` floor, so a table of one showed a tomato
                    // "+1" beside the host: a badge announcing a person who
                    // does not exist, on the first screen every new user
                    // sees. It is an overflow marker, so it appears only
                    // when something has actually overflowed.
                    let others = Array(members.filter { !$0.isOwner }.prefix(2))
                    ForEach(others, id: \.persistentModelID) { member in
                        AvatarCircle(member: member, size: 34)
                            .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 2))
                    }
                    let hidden = seatCount - 1 - others.count
                    if hidden > 0 {
                        AvatarCircle(initials: "+\(hidden)", tone: .tomatoPair, size: 34)
                            .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 2))
                    } else if others.isEmpty {
                        // Nobody else yet. An empty cluster would leave the
                        // control invisible, and the thing you want here is
                        // not a count, it is a way to ask somebody.
                        Circle()
                            .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .frame(width: 34, height: 34)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.inkFaint)
                            }
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Everyone at the Table")

            // The host's own door, the same one the plan and home offer.
            Button {
                Haptic.tap()
                openOwnProfile()
            } label: {
                VStack(spacing: 2) {
                    AvatarCircle(initials: hostInitial, tone: .neutralPair, size: 38,
                                 photo: members.first(where: \.isOwner)?.photoData)
                    Text("HOST")
                        .font(.jakarta(10, .bold))
                        .tracking(0.7)
                        .foregroundStyle(Color.inkFaint)
                }
                // A 38pt avatar is a 38pt target; the law says 44. Home's
                // copy of this control already had the frame.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Your profile")
    }

    private var hostInitial: String {
        String(members.first(where: \.isOwner)?.name.first ?? "Y").uppercased()
    }

    private func openOwnProfile() {
        let me = members.first(where: \.isOwner)
        personShown = PersonRef(name: me?.name ?? "You", colorHex: me?.colorHex ?? "", memberID: me?.persistentModelID)
    }

    /// Everyone or just the household — the X-style split, quiet edition.
    /// The raised pill SLIDES between options (one shared identity), it
    /// doesn't blink out and reappear.
    private var scopePicker: some View {
        HStack(spacing: 0) {
            ForEach(FeedScope.allCases, id: \.self) { option in
                let active = scope == option
                Button {
                    Haptic.select()
                    withAnimation(.plSnap) { scope = option }
                } label: {
                    Text(option.rawValue)
                        .font(.jakarta(13, .bold))
                        .foregroundStyle(active ? Color.ink : Color.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .contentShape(Capsule())
                        .background {
                            if active {
                                Capsule()
                                    .fill(Color.raisedFill)
                                    .overlay(Capsule().strokeBorder(Color.navHairline))
                                    .plTileShadow()
                                    .matchedGeometryEffect(id: "scopePill", in: scopePill)
                            }
                        }
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(2)
        .background(Color.hairlineSoft, in: Capsule())
    }

    // MARK: Cards

    private func postCard(_ post: TablePost) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    openProfile(post)
                } label: {
                    HStack(spacing: 10) {
                        AvatarCircle(initials: post.initials, tone: PersonTone.from(hex: post.authorColorHex), size: 38,
                                     photo: members.photo(forAuthor: post.authorName))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(post.authorName)
                                .plName()
                                .font(.jakarta(14, .bold))
                                .foregroundStyle(Color.ink)
                            HStack(spacing: 5) {
                                Text(postWhen(post.createdAt))
                                    .font(.jakarta(11, .semibold))
                                    .foregroundStyle(Color.inkFaint)
                                // Whose table this came from, said once and
                                // quietly. No badge, no tint: a guest's dish
                                // is not a lesser dish, it just isn't from
                                // this house, and the feed says so without
                                // ranking it.
                                if post.isRemote {
                                    Text("· another table")
                                        .font(.jakarta(11, .semibold))
                                        .foregroundStyle(Color.inkFaint)
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                Spacer()
            }
            .padding(.bottom, 10)

            ZStack(alignment: .topTrailing) {
                if let data = post.photoData, let image = UIImage(data: data) {
                    // The photo is the door to the thread.
                    Button {
                        Haptic.tap()
                        threadPost = post
                    } label: {
                        PhotoWell(image: image, height: 300)
                            .plCardShadow()
                    }
                    .buttonStyle(.pressable)
                }
                if post.hasChefsKiss {
                    chefsKissPill
                        .offset(x: 6, y: -10)
                        // Appears; does not launch. 0.01 threw it in from
                        // a point, which is the fly-in note again.
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }

            HStack(spacing: 14) {
                plateButton(post)
                Button {
                    Haptic.tap()
                    threadPost = post
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "bubble.right")
                            .accessibilityLabel("Comments")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.inkSecondary)
                        Text("\(post.sortedComments.count)")
                            .font(.jakarta(14, .bold))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                Spacer()
                // Save belongs with the things you do to a dish, not up
                // beside the byline where every feed ever built puts
                // follow and more. Same row as the plate and the
                // comments, trailing edge, the way a bookmark sits.
                if isSaved(post) {
                    // A receipt, not a button.
                    HStack(spacing: 5) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Saved")
                            .font(.jakarta(13, .bold))
                    }
                    .foregroundStyle(Color.inkFaint)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Already in your cookbook")
                } else {
                    Button {
                        beginSave(post)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Save")
                                .font(.jakarta(13, .bold))
                        }
                        .foregroundStyle(Color.inkSecondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Opens the recipe so you can make it yours")
                }
            }
            .padding(.top, 10)
            .animation(.plSnap, value: isSaved(post))

            // The composer led with "Name the dish" and then the card never
            // showed the name. What you named is what the table sees.
            if !post.dishTitle.isEmpty {
                Text(post.dishTitle)
                    .font(.gabarito(17, .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.ink)
                    .padding(.top, 4)
            }
            if !post.caption.isEmpty || post.dishTitle.isEmpty {
                (Text(post.authorName).font(.jakarta(14, .bold))
                 + Text("  ").font(.jakarta(14))
                 + Text(post.caption).font(.jakarta(14)))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(3)
                    .padding(.top, post.dishTitle.isEmpty ? 4 : 1)
            }

            ForEach(post.sortedComments.prefix(2), id: \.persistentModelID) { comment in
                commentLine(comment)
            }

            Button {
                Haptic.tap()
                threadPost = post
            } label: {
                Text(post.sortedComments.count > 2
                     ? "See all \(post.sortedComments.count) comments"
                     : "Add a comment")
                    .font(.jakarta(12, .semibold))
                    .foregroundStyle(Color.inkFaint)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .animation(.plPop, value: post.hasChefsKiss)
        .contextMenu { postMenu(post, canSave: true) }
    }

    @ViewBuilder
    private func postMenu(_ post: TablePost, canSave: Bool) -> some View {
        Button {
            Haptic.tap()
            threadPost = post
        } label: {
            Label("Comments", systemImage: "bubble.right")
        }
        if canSave {
            if isSaved(post) {
                Button {} label: {
                    Label("In your cookbook", systemImage: "checkmark")
                }
                .disabled(true)
            } else {
                Button {
                    beginSave(post)
                } label: {
                    Label("Save to cookbook", systemImage: "book")
                }
            }
        }
        Button {
            openProfile(post)
        } label: {
            Label("See \(post.firstName)'s profile", systemImage: "person")
        }
        if isMine(post) {
            Button(role: .destructive) {
                pendingDelete = post
            } label: {
                Label("Delete post", systemImage: "trash")
            }
        }
    }

    /// Already in the cookbook — the button must know before the tap does.
    /// DiscoverPostSheet has carried this state from the start; the feed
    /// offered "Save" on dishes you own and answered with a scolding toast.
    private func isSaved(_ post: TablePost) -> Bool {
        recipes.contains { $0.originID == post.originKey }
    }

    /// First names bridge authors and household members until real user IDs
    /// exist — the same rule `seatCount` uses.
    private func isMine(_ post: TablePost) -> Bool {
        // Anything that arrived over the share belongs to whoever wrote it,
        // whatever they are called. Without this a guest who happens to share
        // the host's first name is offered Delete on the host's own dish —
        // the same name-keying trap the swipe rows hit, and the reason posts
        // now carry an origin and not just a byline.
        guard !post.isRemote else { return false }
        guard let me = members.first(where: \.isOwner)?.name else { return false }
        return post.authorName == me || post.firstName == me
    }

    private func deletePost(_ post: TablePost) {
        Haptic.plate()
        withAnimation(.plSnap) {
            pendingDelete = nil
            context.delete(post)
        }
    }

    private func askCard(_ post: TablePost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    openProfile(post)
                } label: {
                    HStack(spacing: 10) {
                        AvatarCircle(initials: post.initials, tone: PersonTone.from(hex: post.authorColorHex), size: 38,
                                     photo: members.photo(forAuthor: post.authorName))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(post.authorName)
                                .plName()
                                .font(.jakarta(14, .bold))
                                .foregroundStyle(Color.ink)
                            HStack(spacing: 5) {
                                Text(postWhen(post.createdAt))
                                    .font(.jakarta(11, .semibold))
                                    .foregroundStyle(Color.inkFaint)
                                // Whose table this came from, said once and
                                // quietly. No badge, no tint: a guest's dish
                                // is not a lesser dish, it just isn't from
                                // this house, and the feed says so without
                                // ranking it.
                                if post.isRemote {
                                    Text("· another table")
                                        .font(.jakarta(11, .semibold))
                                        .foregroundStyle(Color.inkFaint)
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                Spacer()
                MicroLabel(post.hasPoll ? "Poll" : "Ask")
            }
            Button {
                Haptic.tap()
                threadPost = post
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(post.caption)
                        .font(.jakarta(15, .semibold))
                        .foregroundStyle(Color.ink)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                    if post.hasPoll {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 11, weight: .bold))
                            Text("\(post.pollOptions.count) choices · \(post.totalPollVotes) votes")
                                .font(.jakarta(12, .bold))
                        }
                        .foregroundStyle(Color.basil)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            ForEach(post.sortedComments.prefix(2), id: \.persistentModelID) { comment in
                commentLine(comment)
            }
            Button {
                Haptic.tap()
                threadPost = post
            } label: {
                Text("Suggest a dish…")
                    .font(.jakarta(12, .semibold))
                    .foregroundStyle(Color.inkFaint)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .contextMenu { postMenu(post, canSave: false) }
    }

    private var chefsKissPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.mango)
            Text("Chef's kiss")
                .font(.jakarta(13, .bold))
                .foregroundStyle(Color.ink)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(Color.canvas, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.navHairline))
        .plCardShadow()
    }

    private func plateButton(_ post: TablePost) -> some View {
        Button {
            togglePlate(post)
        } label: {
            HStack(spacing: 7) {
                PlateReactionGlyph(filled: post.platedByMe)
                Text("\(post.totalPlates)")
                    .font(.jakarta(14, .bold))
                    .foregroundStyle(post.platedByMe ? Color.tomato : Color.inkSecondary)
                    .contentTransition(.numericText())
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.pressable)
    }

    private func commentLine(_ comment: TableComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text(comment.authorName).font(.jakarta(13, .bold)).foregroundStyle(Color.ink)
             + Text("  ").font(.jakarta(13))
             + Text(comment.text).font(.jakarta(13)).foregroundStyle(Color.inkSecondary))
                .lineSpacing(2)
            if let url = URL.webLink(comment.linkURL) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .bold))
                        Text(comment.linkLabel)
                            .font(.jakarta(12, .bold))
                    }
                    .foregroundStyle(Color.tomato)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
                    .background(Color.chipFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.navHairline))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Actions

    private func togglePlate(_ post: TablePost) {
        let turningOn = !post.platedByMe
        withAnimation(.plPop) {
            post.platedByMe.toggle()
            bouncePost = post.persistentModelID
        }
        if turningOn {
            post.hasChefsKiss ? Haptic.kiss() : Haptic.plate()
            let me = members.first(where: \.isOwner)?.name ?? "You"
            if post.firstName != me && post.authorName != me {
                // Once per post, ever — plate/unplate/plate must not spam.
                Notifier.postOnce(
                    key: "plate:\(post.originKey)|\(Int(post.createdAt.timeIntervalSince1970))",
                    .plateReaction, actor: me,
                    body: "\(me) plated \(post.firstName)'s \(post.dishTitle.isEmpty ? "post" : post.dishTitle).",
                    into: context
                )
            }
        } else {
            Haptic.tap()
        }
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            if bouncePost == post.persistentModelID {
                withAnimation(.plSnap) { bouncePost = nil }
            }
        }
    }

    /// Save now opens the editor prefilled — tweak the category, fix the
    /// ingredients, then it joins your cookbook. Already-saved dishes skip
    /// straight to the toast.
    private func beginSave(_ post: TablePost) {
        Haptic.tap()
        if recipes.contains(where: { $0.originID == post.originKey }) {
            showToast("Already in your cookbook")
            return
        }
        editingSave = post
    }

    private func finishSave(_ post: TablePost) {
        // Saving your own dish back is a legitimate move (post first, keep
        // it later) — but crediting yourself and ringing the household bell
        // about it is the app talking to itself.
        if isMine(post) {
            showToast("Saved to your cookbook")
            return
        }
        // The author gets the credit — a save is the sincerest form of
        // dinner flattery. Local ledger today, real push later.
        Awards.recordSaveReceived(by: post.authorName)
        let me = members.first(where: \.isOwner)?.name ?? "Someone"
        Notifier.post(
            .saveReceived, actor: me,
            body: "\(me) saved \(post.firstName)'s \(post.dishTitle.isEmpty ? "dish" : post.dishTitle).",
            into: context
        )
        showToast("Saved to your cookbook")
    }

    private func showToast(_ message: String) {
        // The confirmation reaches the hand as well as the eye.
        Haptic.tap()
        toastToken += 1
        let token = toastToken
        withAnimation(.plSnap) { savedToast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toastToken == token {
                withAnimation(.plSnap) { savedToast = nil }
            }
        }
    }

    private func openProfile(_ post: TablePost) {
        Haptic.tap()
        personShown = PersonRef.author(
            post.authorName, colorHex: post.authorColorHex, in: members
        )
    }

    private func postWhen(_ date: Date) -> String {
        let time = DateFormatter()
        time.dateFormat = "h:mm a"
        if Calendar.current.isDateInToday(date) {
            let hour = Calendar.current.component(.hour, from: date)
            return "\(hour >= 17 ? "Tonight" : "Today") · \(time.string(from: date))"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday · \(time.string(from: date))"
        }
        let day = DateFormatter()
        day.dateFormat = "EEEE"
        return "\(day.string(from: date)) · \(time.string(from: date))"
    }
}

/// The plate reaction mark. At rest it is an actual plate — rim outside,
/// well inside — so nobody mistakes it for an empty radio button; filled,
/// it goes tomato with the well knocked out in canvas.
struct PlateReactionGlyph: View {
    var filled: Bool
    /// The count and badge shelves borrow this mark rather than reaching
    /// for a stock symbol — the app already owns a plate, and `hands.clap`
    /// standing in for one was the loudest wrong note on the stats page.
    var size: CGFloat = 26
    /// The rim colour when empty, so the tone can travel with the size.
    var tone: Color = .inkSecondary

    private var scale: CGFloat { size / 26 }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(filled ? Color.tomato : tone, lineWidth: 2 * scale)
                .background(Circle().fill(filled ? Color.tomato : Color.clear))
                .frame(width: size, height: size)
            if filled {
                Circle()
                    .fill(Color.canvas)
                    .frame(width: 9 * scale, height: 9 * scale)
            } else {
                Circle()
                    .strokeBorder(tone, lineWidth: 1.5 * scale)
                    .frame(width: 13 * scale, height: 13 * scale)
            }
        }
    }
}

/// The same reaction, self-contained for the thread view.
struct PlateReactionButton: View {
    let post: TablePost
    @Binding var bounce: Bool

    @Environment(\.modelContext) private var context
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    var body: some View {
        Button {
            let turningOn = !post.platedByMe
            withAnimation(.plPop) {
                post.platedByMe.toggle()
                bounce = true
            }
            if turningOn {
                post.hasChefsKiss ? Haptic.kiss() : Haptic.plate()
                let me = members.first(where: \.isOwner)?.name ?? "You"
                if post.firstName != me && post.authorName != me {
                    Notifier.postOnce(
                        key: "plate:\(post.originKey)|\(Int(post.createdAt.timeIntervalSince1970))",
                        .plateReaction, actor: me,
                        body: "\(me) plated \(post.firstName)'s \(post.dishTitle.isEmpty ? "post" : post.dishTitle).",
                        into: context
                    )
                }
            } else {
                Haptic.tap()
            }
            Task {
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.plSnap) { bounce = false }
            }
        } label: {
            PlateReactionGlyph(filled: post.platedByMe)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.pressable)
    }
}
