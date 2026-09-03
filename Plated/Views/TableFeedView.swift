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
    /// The plate that just landed on a photograph, for the 320ms it shows.
    ///
    /// This existed as `bouncePost`: set, timed and torn down at two sites,
    /// and read by no modifier anywhere. The animation wrapper, the timer and
    /// the teardown were all there and the visual never was. It is spent on
    /// the double-tap now, which is the one gesture in the app whose control
    /// is nowhere near the finger — the plate button is at the other end of
    /// the card, so without a mark on the photo a double-tap looks like
    /// nothing happened.
    ///
    /// DESIGN.md permits this and only this: the mark is what changed, drawn
    /// where the change was asked for. It is not a flourish about a tap; a
    /// tap on the plate button itself gets no burst, because there the
    /// control you touched is the thing that changed.
    @State private var burstPost: PersistentIdentifier?
    @State private var threadPost: TablePost?
    /// Set only when the door was the "Add a comment" line, so the thread
    /// opens with the field ready. Reading a thread should not raise a
    /// keyboard over it.
    @State private var threadStartsWriting = false
    @State private var personShown: PersonRef?
    @State private var seatsPresented = false
    /// The composer, opened straight from the empty state. The + in the tab
    /// bar owns the same sheet, but an empty screen that can only be
    /// answered by a control somewhere else is a dead end.
    @State private var composerShown = false
    @State private var editingSave: TablePost?
    @State private var savedToast: String?
    /// The post you tapped is the post that opens. See CookbookView.
    @Namespace private var zoom
    /// Captions clipped to three lines, and the ones a reader has opened.
    @State private var truncatedCaptions: Set<PersistentIdentifier> = []
    @State private var expandedCaptions: Set<PersistentIdentifier> = []
    /// What the app actually knows about the Table right now, as opposed to
    /// what it can show. These were one screen: an empty table, a table that
    /// hadn't been checked yet, and a table we couldn't reach all drew the
    /// same "Nothing plated yet" over the same invitation to post. The last
    /// of those is a claim about other people's dinners that we had not
    /// earned. `refreshFeed` already knew the difference and spent it on a
    /// haptic.
    @State private var reach: Reach = .looking
    @State private var hasLooked = false

    private enum Reach { case looking, reached, unreachable }
    @State private var toastToken = 0
    /// One destination, not two flags.
    ///
    /// These were two `navigationDestination(isPresented:)` modifiers on one
    /// NavigationStack, which is the same undefined behaviour as two `.sheet`
    /// modifiers on one view — the trap CLAUDE.md already records. SwiftUI
    /// honoured the first and silently dropped the second, so the search
    /// button on the Table opened nothing and Discover was unreachable from
    /// the app: a control sitting in the masthead doing precisely nothing,
    /// which is the honesty rule broken by the navigation layer rather than
    /// by the copy. Same shape as WeekView.PlanDestination.
    enum TableDestination: String, Identifiable {
        case activity, discover
        var id: String { rawValue }
    }
    @State private var pushed: TableDestination?
    /// Long-press on a post. Feed cards aren't swipeable — a plate is a tap
    /// and the photo is a door — so the menu carries the rest.
    @State private var pendingDelete: TablePost?
    @State private var editingPost: TablePost?
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
    /// Anything of ours that never made it out of the phone.
    ///
    /// `publish` is fire-and-forget from the composer, deliberately, so a
    /// post written with no signal, no iCloud account or a dropped
    /// connection keeps an empty `shareRecordName` forever. The comment at
    /// that call site says a failure "leaves shareRecordName empty, which is
    /// exactly the state the next publish attempt looks for" — and there was
    /// no next publish attempt anywhere in the app. The post sat on one
    /// phone, looking exactly like a post that had gone out, for good.
    ///
    /// This is that attempt. It runs on every pull and on the feed's first
    /// appearance, and it is idempotent: `publish` reuses a name it is
    /// given, so a post that turns out to have gone after all is overwritten
    /// with itself rather than duplicated.
    /// Ours, minted more than a minute ago, and still not on the table.
    ///
    /// The retry above will keep trying, but a person is entitled to know
    /// that the thing they posted is not somewhere anybody else can see it.
    /// Silence here would be the app claiming a post happened.
    private func stranded(_ post: TablePost) -> Bool {
        !post.isRemote
            && post.shareRecordName.isEmpty
            && Date.now.timeIntervalSince(post.createdAt) > 60
    }

    private func publishBacklog() async {
        let stranded = posts.filter { !$0.isRemote && $0.shareRecordName.isEmpty }
        guard !stranded.isEmpty else { return }
        let hostName = members.first(where: \.isOwner)?.name ?? ""
        var sent = false
        for post in stranded {
            if let name = await TableShare.publish(post, hostName: hostName) {
                post.shareRecordName = name
                sent = true
            }
        }
        if sent { Persist.save(context, "publish backlog") }
    }

    private func refreshFeed() async {
        Persist.save(context)
        await publishBacklog()
        // Two different pipes, pulled together because the user pulled once.
        // The mirror carries this household's own devices; TableShare
        // carries everybody else's table. Neither knows about the other.
        async let remote = TableShare.fetchChanges()
        let outcome = await CloudSync.waitForImport()
        TableShare.merge(await remote, into: context)
        // Let go mid-pull and there is nothing to confirm — the tick used
        // to fire anyway, because `try?` around the sleep swallowed the
        // cancellation and left the call site unable to tell an abandoned
        // refresh from a finished one.
        guard !Task.isCancelled else { return }
        switch outcome {
        case .arrived, .quiet:
            reach = .reached
            Haptic.tap()
        case .failed:
            reach = .unreachable
            Haptic.warn()
        }
    }

    // MARK: The three empty tables

    /// Still asking. Only ever seen on a cold launch with nothing cached,
    /// and only for as long as the ask takes.
    private var lookingForPosts: some View {
        ProgressView()
            .controlSize(.regular)
            .tint(Color.inkFaint)
            .padding(.top, 80)
            .accessibilityLabel("Looking for new posts")
    }

    /// Asked, and got an answer: nobody has posted. This is the only one of
    /// the three that may say so, because it is the only one that knows.
    private var nothingPlatedYet: some View {
        VStack(spacing: 10) {
            PlateReactionGlyph(filled: false)
            Text(scope == .household ? "Your household hasn't posted yet" : "Nothing plated yet")
                .plType(.body, .bold)
                .foregroundStyle(Color.ink)
            Text("Only the people you invite can see it.")
                .plType(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
            Button {
                Haptic.tap()
                composerShown = true
            } label: {
                Text("Post a dish")
                    .plType(.body, .bold)
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

    /// Couldn't ask. Says exactly that and no more: it does not know whether
    /// anybody has posted, so it does not get to say "nothing plated yet",
    /// and it does not get to invite you to fill a silence that might not
    /// be one.
    private var cannotReachTable: some View {
        VStack(spacing: 10) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.inkFaint)
            Text("Couldn't check for new dishes")
                .plType(.body, .bold)
                .foregroundStyle(Color.ink)
            Text("What's here is what's on this phone.")
                .plType(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
            Button {
                Haptic.tap()
                reach = .looking
                Task { await refreshFeed() }
            } label: {
                // Outlined, not filled. `Color.fill` is this app's selection
                // ground, and a retry is not a selected thing — I wrote this
                // one earlier today and reached for the wrong idiom, which
                // is the whole argument for the shared atoms.
                Text("Try again")
                    .plType(.callout)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 44)
                    .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .padding(.top, 4)
        }
        .padding(.top, 60)
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
                                    .plType(.micro, .semibold)
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
                        pushed = .discover
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
                        }
                        ForEach(Array(shownPosts.enumerated()),
                                id: \.element.persistentModelID) { index, post in
                            // Before each card except the very first thing in
                            // the list, never after the last. A separator marks
                            // the boundary BETWEEN two rows; trailing the final
                            // one, the feed ended on a hairline with nothing
                            // under it but the floating bar's inset.
                            if index > 0 || (scope == .everyone && !invitedSeats.isEmpty) {
                                Divider().overlay(Color.hairlineSoft)
                            }
                            Group {
                                if post.kind == "ask" {
                                    askCard(post)
                                } else {
                                    postCard(post)
                                }
                            }
                            // Both card kinds are doors to the same thread,
                            // so the source sits above the branch.
                            .matchedTransitionSource(id: post.persistentModelID, in: zoom)
                        }
                        if shownPosts.isEmpty {
                            switch reach {
                            case .looking: lookingForPosts
                            case .unreachable: cannotReachTable
                            case .reached: nothingPlatedYet
                            }
                        }
                    }
                    .padding(.bottom, Layout.floatingChromeInset)
                }
                .refreshable { await refreshFeed() }
                .task {
                    guard !hasLooked else { return }
                    hasLooked = true
                    // Seed the ledger from the fields that used to hold
                    // this, once, before anything reads it.
                    TableReactions.backfill(posts, context: context)
                    // Ask CloudKit who we are. A placeholder minted while
                    // offline is re-attributed the moment a real id arrives,
                    // so nothing tapped on a plane is orphaned.
                    let before = TableIdentity.cached
                    if let real = await TableIdentity.confirm(), real != before {
                        TableLedger.shared.reattribute(from: before, to: real)
                        TableOutbox.shared.reattribute(from: before, to: real)
                    }
                    await refreshFeed()
                }
                // A seat accepted from Messages while the Table is already
                // open would otherwise sit invisible until the next pull.
                .onReceive(NotificationCenter.default.publisher(for: ShareAcceptor.didAccept)) { _ in
                    Task { TableShare.merge(await TableShare.fetchChanges(), into: context) }
                }
            }
            .background(Color.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .plSwipeBack()
            .sheet(isPresented: $composerShown) { TableComposerSheet() }
            .navigationDestination(item: $threadPost) { post in
                PostThreadView(post: post, startWriting: threadStartsWriting) { beginSave($0) }
                    .navigationTransition(.zoom(sourceID: post.persistentModelID, in: zoom))
            }
            .navigationDestination(item: $personShown) { person in
                PersonProfileView(personName: person.name, colorHex: person.colorHex, memberID: person.memberID)
            }
            // Discover and Activity both read as pushed screens — they wear
            // the back chevron — so they are, and they inherit the edge swipe
            // with the rest.
            .navigationDestination(item: $pushed) { destination in
                switch destination {
                case .activity: NotificationsView()
                case .discover: DiscoverView()
                }
            }
        }
        .sheet(isPresented: $seatsPresented) {
            TableSeatsSheet()
        }
        .confirmationDialog(
            pendingDelete.map { $0.dishTitle.isEmpty ? "Delete this post?" : "Delete \($0.dishTitle)?" }
                ?? "Delete this post?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let post = pendingDelete {
                Button("Delete", role: .destructive) { deletePost(post) }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            // "Everyone" is now a promise the code keeps. It used to delete
            // the local row only, and the post came back on the next pull.
            Text("It comes off the table for everyone. The photo and comments go too.")
        }
        .sheet(item: $editingPost) { post in
            PostEditSheet(post: post)
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
                pushed = .discover
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
                    .plType(.footnote, .bold)
                    .foregroundStyle(Color.canvas)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .background(Color.ink, in: Capsule())
                    // The perch occupies 84…134; a hand-typed 100 put a long
                    // toast underneath it. The last bottom inset on the
                    // branch that hadn't gone through the token family the
                    // rest of this class was built to fix.
                    .padding(.bottom, Layout.floatingChromeInset)
                    .transition(.plRise)
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
            // Aligned on the discs, not the blocks. See
            // VerticalAlignment.discCentre.
            HStack(alignment: .discCentre, spacing: 12) {
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
                    .plType(.display)
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
                pushed = .activity
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
                        .plType(.micro)
                        .foregroundStyle(Color.inkSecondary)
                        // One line, always. This sits in a squeezed masthead
                        // HStack, so at XXXL it wrapped and broke the word
                        // across two lines: "HO" over "ST".
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                // A 38pt avatar is a 38pt target; the law says 44. Home's
                // copy of this control already had the frame.
                .plTapTarget()
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Your profile")
            .plDiscAligned(38)
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
                        .plType(.footnote, .bold)
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
                .accessibilityAddTraits(active ? .isSelected : [])
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
                                .plType(.body, .bold)
                                .foregroundStyle(Color.ink)
                            HStack(spacing: 5) {
                                Text(postWhen(post.createdAt))
                                    .plType(.micro, .semibold)
                                    .foregroundStyle(Color.inkSecondary)
                                // Whose table this came from, said once and
                                // quietly. No badge, no tint: a guest's dish
                                // is not a lesser dish, it just isn't from
                                // this house, and the feed says so without
                                // ranking it.
                                if post.isRemote {
                                    Text("· another table")
                                        .plType(.micro, .semibold)
                                        .foregroundStyle(Color.inkSecondary)
                                }
                                // Only once it has genuinely been sitting.
                                // Publishing is attempted the moment a post
                                // is written, so a marker with no delay
                                // would flash on every single post; a minute
                                // means it really has not gone.
                                if stranded(post) {
                                    Text("· Not sent yet")
                                        .plType(.micro, .semibold)
                                        .foregroundStyle(Color.inkSecondary)
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                Spacer()
                // The overflow, where every social app puts it: trailing
                // edge of the byline row, on the avatar's centreline.
                //
                // Everything in this menu was already here and reachable
                // only by long-pressing the card, which is a gesture nobody
                // is told about — so "delete the thing I just posted", the
                // one action a person is most certain they should have, was
                // effectively missing. DESIGN.md already says a gesture
                // nobody is told about is not a feature most people have.
                // The long press still works as an accelerator.
                Menu {
                    postMenu(post, canSave: true)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                        .plTapTarget()
                }
                .accessibilityLabel("More")
            }
            .padding(.bottom, 10)

            ZStack(alignment: .topTrailing) {
                if let data = post.photoData, let image = UIImage(data: data) {
                    // The photo is the door to the thread.
                    Button {
                        openThread(post)
                    } label: {
                        PhotoWell(image: image, clamped: true)
                            .plCardShadow()
                    }
                    .buttonStyle(.pressable)
                    // Double-tap plates it, add-only, the way Instagram and
                    // Messages both do: a second double-tap is a no-op and
                    // the button in the row below stays the only way to
                    // take a plate back. highPriority, or the Button under
                    // it swallows the first tap and opens the thread.
                    .highPriorityGesture(
                        TapGesture(count: 2).onEnded {
                            guard !post.platedByMeNow else { return }
                            togglePlate(post)
                            withAnimation(.plPop) {
                                burstPost = post.persistentModelID
                            }
                        }
                    )
                }
                if burstPost == post.persistentModelID {
                    PlateReactionGlyph(filled: true, size: 92)
                        .plFloatShadow()
                        .transition(.plArrive)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if post.hasChefsKiss(seats: members.count) {
                    chefsKissPill
                        .offset(x: 6, y: -10)
                        // Appears; does not launch. 0.01 threw it in from
                        // a point, which is the fly-in note again.
                        .transition(.plArrive)
                }
            }

            // The dish and what was said about it come before the row of
            // things you can do to them. They used to sit after, which is
            // Instagram's order and works while there is a photograph for
            // the actions to hang under. A post with no photo put a plate
            // reaction and a Save above the dish's own name: you were asked
            // what you thought of it before you were told what it was.
            // The composer led with "Name the dish" and then the card never
            // showed the name. What you named is what the table sees.
            // The words are a door too, not just the photograph.
            //
            // A dish posted without a photo rendered no well, no placeholder
            // and no outline, and its title and caption were plain Text, so
            // the card had a hole where the image goes and no way into the
            // thread at all. Threads solves it the same way: with no media
            // the text becomes the tap target.
            Button {
                openThread(post)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    if !post.dishTitle.isEmpty {
                        Text(post.dishTitle)
                            .plType(.heading)
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    if !post.caption.isEmpty || post.dishTitle.isEmpty {
                        captionText(post)
                            // Three lines, then "more". Unbounded, a twelve
                            // line caption pushed the plate, the comments
                            // and Save clean off the bottom of the card.
                            // Three rather than Instagram's one: these are
                            // sentences about food from people you know, and
                            // clipping at one would make the expander a
                            // required tap on nearly every post.
                            .lineLimit(expandedCaptions.contains(post.persistentModelID) ? nil : 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, post.dishTitle.isEmpty ? 4 : 1)
                            .background {
                                // Did the unclipped text fit in the space the
                                // clipped one took? If not, this branch loses
                                // and we know to offer "more".
                                ViewThatFits(in: .vertical) {
                                    captionText(post).hidden()
                                    Color.clear.onAppear {
                                        truncatedCaptions.insert(post.persistentModelID)
                                    }
                                }
                            }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            if truncatedCaptions.contains(post.persistentModelID),
               !expandedCaptions.contains(post.persistentModelID) {
                Button {
                    withAnimation(.plSnap) {
                        _ = expandedCaptions.insert(post.persistentModelID)
                    }
                } label: {
                    Text("more")
                        .plType(.footnote, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }


            HStack(spacing: 14) {
                plateButton(post)
                Button {
                    openThread(post)
                } label: {
                    HStack(spacing: 7) {
                        // 20pt semibold, matched to PlateReactionGlyph's
                        // stroke rather than to its own idea of a size. The
                        // three controls on this row were a 26pt hand-drawn
                        // glyph with a 2pt rim, an 18pt medium symbol and a
                        // 14pt semibold one: three optical weights on one
                        // baseline, where Instagram's row is one.
                        Image(systemName: "bubble.right")
                            .accessibilityLabel("Comments")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.inkSecondary)
                        // Same rule as the plate: the count is evidence, not
                        // furniture. The "Add a comment" row below already
                        // carries the invitation, so nothing is lost.
                        if !post.sortedComments.isEmpty {
                            Text("\(post.sortedComments.count)")
                                .plType(.body, .bold)
                                .foregroundStyle(Color.inkSecondary)
                        }
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
                // One control in both states, not two. An `if/else` swaps
                // SwiftUI's identity, so the bookmark was torn down and
                // rebuilt and no transition could survive it. It also left
                // a saved dish with a dead-looking label where a control
                // had been — `beginSave` already answers a second tap with
                // "Already in your cookbook", which is a better reply than
                // nothing happening.
                let saved = isSaved(post)
                Button {
                    beginSave(post)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: saved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 20, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
                        Text(saved ? "Saved" : "Save")
                            .plType(.footnote, .bold)
                    }
                    .foregroundStyle(Color.inkSecondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(saved ? "Saved to your cookbook" : "Save")
                .accessibilityHint(saved ? "" : "Opens the recipe so you can make it yours")
            }
            .padding(.top, 10)
            .animation(.plSnap, value: isSaved(post))
            // The newest two, not the oldest two. `sortedComments` is
            // ascending, so `prefix(2)` pinned the preview to the first
            // two things ever said and it never changed again however
            // busy the thread got. Instagram previews the most recent,
            // and in a table of eight the line that just changed is the
            // whole point.
            ForEach(post.sortedComments.suffix(2), id: \.persistentModelID) { comment in
                commentLine(comment)
            }

            Button {
                openThread(post, writing: post.sortedComments.count <= 2)
            } label: {
                Text(post.sortedComments.count > 2
                     ? "See all \(post.sortedComments.count) comments"
                     : "Add a comment")
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .animation(.plPop, value: post.hasChefsKiss(seats: members.count))
        .contextMenu { postMenu(post, canSave: true) }
    }

    @ViewBuilder
    private func postMenu(_ post: TablePost, canSave: Bool) -> some View {
        Button {
            openThread(post)
        } label: {
            Label("Comments", systemImage: "bubble.right")
        }
        if canSave {
            // Only when there is something to do. A dimmed, inert
            // "In your cookbook" row was a label wearing a button's clothes,
            // and it sat in the menu forever once a dish was saved.
            if !isSaved(post) {
                Button {
                    beginSave(post)
                } label: {
                    Label("Save to cookbook", systemImage: "book")
                }
            }
        }
        // Not on your own post. This offered "See Nate's profile" to Nate,
        // which is the tell that one menu was being conditionally hidden
        // rather than two menus being written.
        if !isMine(post) {
            Button {
                openProfile(post)
            } label: {
                Label("See \(post.firstName)'s profile", systemImage: "person")
            }
        }
        if isMine(post) {
            // Your own post's actions, in their own section. A menu that
            // mixes "see Nate's profile" with "delete Nate's post" while
            // Nate is reading it is one menu doing two jobs.
            Section {
                Button {
                    editingPost = post
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    pendingDelete = post
                } label: {
                    Label("Delete post", systemImage: "trash")
                }
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

    /// The record first, the row second.
    ///
    /// This used to be `context.delete(post)` alone, which does not delete
    /// anything anybody else can see. `merge` keys on `shareRecordName`, so
    /// the record left behind in the zone came back on the very next pull as
    /// a NEW post stamped `isRemote = true`: your own dinner, returned to
    /// your feed as a stranger's, without its plates or comments, and
    /// undeletable forever after because `isMine` refuses remote posts.
    ///
    /// So the local row only goes when the record is confirmed gone. If
    /// iCloud cannot be reached the post stays exactly where it is and says
    /// so, because a delete that half happened is worse than one that did
    /// not: DESIGN.md's rule is that state is recorded, never asserted.
    private func deletePost(_ post: TablePost) {
        let recordName = post.shareRecordName
        let zoneOwner = post.shareZoneOwner
        pendingDelete = nil
        Task {
            guard await TableShare.retract(recordName: recordName, zoneOwner: zoneOwner) else {
                Haptic.warn()
                showToast("Couldn't reach iCloud. The post is still on the table.")
                return
            }
            Haptic.plate()
            withAnimation(.plSnap) { context.delete(post) }
            Persist.save(context)
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
                                .plType(.body, .bold)
                                .foregroundStyle(Color.ink)
                            HStack(spacing: 5) {
                                Text(postWhen(post.createdAt))
                                    .plType(.micro, .semibold)
                                    .foregroundStyle(Color.inkSecondary)
                                // Whose table this came from, said once and
                                // quietly. No badge, no tint: a guest's dish
                                // is not a lesser dish, it just isn't from
                                // this house, and the feed says so without
                                // ranking it.
                                if post.isRemote {
                                    Text("· another table")
                                        .plType(.micro, .semibold)
                                        .foregroundStyle(Color.inkSecondary)
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                Spacer()
                MicroLabel(post.hasPoll ? "Poll" : "Ask")
                // The same overflow the dish cards carry. An ask is a post
                // too, and its author has the same right to take it back.
                Menu {
                    postMenu(post, canSave: false)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                        .plTapTarget()
                }
                .accessibilityLabel("More")
            }
            Button {
                openThread(post)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(post.caption)
                        .plType(.body)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    if post.hasPoll {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 11, weight: .bold))
                            Text("\(post.pollOptions.count) choices · \(post.totalPollVotes) votes")
                                .plType(.micro)
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
            ForEach(post.sortedComments.suffix(2), id: \.persistentModelID) { comment in
                commentLine(comment)
            }
            Button {
                openThread(post, writing: post.sortedComments.count <= 2)
            } label: {
                // The same branch the dish card already has, worded for
                // an ask. This always said "Suggest a dish", so a question
                // with five answers on it looked exactly like one with none.
                Text(post.sortedComments.count > 2
                     ? "See all \(post.sortedComments.count) suggestions"
                     : "Suggest a dish")
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
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
                .plType(.footnote, .bold)
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
                PlateReactionGlyph(filled: post.platedByMeNow)
                // The numeral arrives with the first plate and not before.
                // A mounted zero beside every dinner somebody cooked is not
                // neutral in a room of eight people; it reads as a verdict
                // on a post nobody has got to yet. Instagram draws no like
                // row at zero, Slack no pill, Messages no chip: a reaction
                // display is evidence that something happened, never a
                // counter waiting to be filled.
                if post.totalPlates > 0 {
                    Text("\(post.totalPlates)")
                        .plType(.body, .bold)
                        .foregroundStyle(post.platedByMeNow ? Color.tomato : Color.inkSecondary)
                        .contentTransition(.numericText())
                }
            }
            .animation(.plSnap, value: post.totalPlates)
            .plTapTarget()
        }
        .buttonStyle(.pressable)
    }

    private func commentLine(_ comment: TableComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text(comment.authorName).font(.jakarta(TypeScale.footnote.size, .bold)).foregroundStyle(Color.ink)
             + Text("  ").font(.jakarta(TypeScale.footnote.size))
             + Text(comment.text).font(.jakarta(TypeScale.footnote.size)).foregroundStyle(Color.inkSecondary))
                .lineSpacing(2)
            if let url = URL.webLink(comment.linkURL) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .bold))
                        Text(comment.linkLabel)
                            .plType(.micro)
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
        var turningOn = false
        withAnimation(.plPop) {
            turningOn = TableReactions.togglePlate(post)
        }
        if turningOn {
            post.hasChefsKiss(seats: members.count) ? Haptic.kiss() : Haptic.plate()
            // NO notification here, deliberately.
            //
            // `Notifier.postOnce` writes into the LOCAL context, and plates
            // do not cross the wire, so this row only ever reached the
            // person who tapped it. Your own activity bell filled with
            // third-person narration of things you had just done — "Nate
            // plated Riley's ragù", in Nate's bell — and Riley was never
            // told anything. Instagram's rule is that a like never appears
            // in the liker's own activity, because you already know what
            // you did.
            //
            // The de-dup key below was well built and is worth restoring
            // the moment plates actually reach the author:
            //   key: "plate:\(post.originKey)|\(Int(post.createdAt.timeIntervalSince1970))"
        } else {
            Haptic.tap()
        }
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            if burstPost == post.persistentModelID {
                withAnimation(.plSnap) { burstPost = nil }
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

    /// A stamp is never allowed to be ambiguous about which week it means.
    ///
    /// This fell through to a bare weekday with no bound on age, so a post
    /// from three Thursdays ago read "Thursday · 7:42 PM" and asserted it
    /// was last Thursday. Instagram, Threads, Slack and Messages all run a
    /// relative stamp only while it can mean one thing and then hand off to
    /// something absolute; that hand-off is the whole invariant.
    ///
    /// The formatters are static because this runs once per card per body
    /// pass and `DateFormatter()` is expensive to build.
    private static let timeFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private static let weekdayFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
    private static let dateFormat: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM"); return f
    }()
    private static let datedYearFormat: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM yyyy"); return f
    }()

    /// The byline-and-caption run, built once so the visible copy and the
    /// hidden measuring copy can never drift apart.
    ///
    /// Concatenated Text takes a Font, not a view modifier, so the scale is
    /// spelled out rather than applied. These are TypeScale.body's numbers;
    /// keep them in step with it.
    private func captionText(_ post: TablePost) -> some View {
        (Text(post.authorName).font(.jakarta(TypeScale.body.size, .bold))
         + Text("  ").font(.jakarta(TypeScale.body.size))
         + Text(post.caption).font(.jakarta(TypeScale.body.size)))
            .foregroundStyle(Color.ink)
            .lineSpacing(3)
    }

    /// One door into a thread, and whether it was a reading door or a
    /// writing one.
    ///
    /// "Add a comment" is a verb naming an outcome and it used to push a page
    /// and ask you to tap again. It arrives with the field ready now. The
    /// photograph, the words, the comment glyph and the overflow all mean
    /// "let me read this", and a keyboard over a thread you came to read is
    /// worse than no keyboard at all.
    private func openThread(_ post: TablePost, writing: Bool = false) {
        Haptic.tap()
        threadStartsWriting = writing
        threadPost = post
    }

    private func postWhen(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = Self.timeFormat.string(from: date)
        if calendar.isDateInToday(date) {
            let hour = calendar.component(.hour, from: date)
            return "\(hour >= 17 ? "Tonight" : "Today") · \(time)"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday · \(time)"
        }
        // A weekday only while it still means one thing: six days back, so
        // "Thursday" can never collide with the Thursday before it.
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: .now)).day ?? 0
        if days < 6 {
            return "\(Self.weekdayFormat.string(from: date)) · \(time)"
        }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return Self.dateFormat.string(from: date)
        }
        return Self.datedYearFormat.string(from: date)
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
            var turningOn = false
            withAnimation(.plPop) {
                turningOn = TableReactions.togglePlate(post)
                bounce = true
            }
            if turningOn {
                post.hasChefsKiss(seats: members.count) ? Haptic.kiss() : Haptic.plate()
                // The second copy of the notification removed in
                // togglePlate above, and the same reason: it was written
                // into the local context, so it only ever reached the
                // person who tapped it.
            } else {
                Haptic.tap()
            }
            Task {
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.plSnap) { bounce = false }
            }
        } label: {
            PlateReactionGlyph(filled: post.platedByMeNow)
                .plTapTarget()
        }
        .buttonStyle(.pressable)
    }
}
