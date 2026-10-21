import SwiftUI
import SwiftData

/// The Table — the private feed. Reactions are plates; ten plates and the
/// dish earns its chef's kiss. Split like a good timeline: Everyone at
/// your table, or just the household. Posts open into pages, names open
/// into profiles, and saving a dish lets you make it yours first.
struct TableFeedView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.activeAppTab) private var activeAppTab
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(
        filter: #Predicate<TablePost> { !$0.isDiscover },
        sort: \TablePost.createdAt, order: .reverse
    ) private var posts: [TablePost]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var recipes: [Recipe]

    enum FeedScope: String, CaseIterable {
        case everyone = "Your Table"
        case household = "Household"
    }

    @State private var scope: FeedScope = .everyone
    /// Bumped when a dish is muted or unmuted, so the card's glyph follows.
    @State private var muteVersion = 0
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
    @Environment(\.tabPop) private var tabPop
    @State private var threadPost: TablePost?
    /// Set only when the door was the "Add a comment" line, so the thread
    /// opens with the field ready. Reading a thread should not raise a
    /// keyboard over it.
    @State private var threadTargetComment: String?
    @State private var threadStartsWriting = false
    @State private var personShown: PersonRef?
    /// Which door this profile was opened through. The Table offers two —
    /// the masthead face and an author's face on a post — and DESIGN.md's
    /// rule is that the tap records which one, rather than two sources
    /// sharing an id.
    @State private var personDoor: ZoomID = .host
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

    /// Screenshot-only states over the in-memory design-review store. They
    /// never touch or clear real posts, and the extra flag is ignored unless
    /// the app is already on its explicit `-plated-design-review` route.
    private enum ReviewState { case standard, empty, loading, error }
    private var reviewState: ReviewState {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-plated-design-review") else { return .standard }
        if arguments.contains("-plated-review-table-empty") { return .empty }
        if arguments.contains("-plated-review-table-loading") { return .loading }
        if arguments.contains("-plated-review-table-error") { return .error }
        #endif
        return .standard
    }
    /// A single typed destination keeps the bell's push state explicit.
    enum TableDestination: String, Identifiable {
        case activity
        var id: String { rawValue }
    }
    @State private var pushed: TableDestination?
    /// Long-press on a post. Feed cards aren't swipeable — a plate is a tap
    /// and the photo is a door — so the menu carries the rest.
    @State private var pendingDelete: TablePost?
    @State private var editingPost: TablePost?
    @State private var publication = TablePostPublication.shared
    @State private var network: NetworkAvailability?
    @State private var initialIdentityChecked = false
    @State private var backlogPass = TablePostPublication.BacklogPass()
    private struct DeferredRecoveryWork {
        let id: UUID
        let account: String
        let task: Task<Void, Never>
    }
    @State private var deferredRecoveryWork: DeferredRecoveryWork?

    private var publicationConnection: NetworkAvailability.State {
        #if DEBUG
        if PlatedApp.usesPreviewContainer {
            return ProcessInfo.processInfo.arguments.contains("-plated-review-publication-waiting")
                ? .unavailable : .unknown
        }
        #endif
        return network?.state ?? .unknown
    }

    private var backlogRecovery: TablePostPublication.RecoveryContext {
        .init(connection: publicationConnection, isForeground: scenePhase == .active,
              isTableActive: activeAppTab == .table, isPreview: PlatedApp.usesPreviewContainer,
              isIdentityReady: initialIdentityChecked)
    }
    private struct DeferredRecoveryTrigger: Equatable {
        let context: TablePostPublication.RecoveryContext
        let account: String
        let revision: UInt64
    }
    private var deferredRecoveryTrigger: DeferredRecoveryTrigger {
        .init(context: backlogRecovery, account: TableIdentity.cached,
              revision: publication.recoveryRevision)
    }
    @State private var contentSafety = ContentSafety.shared
    @State private var safetyDialog: SafetyDialog?

    private enum SafetyDialog {
        case report(ContentSafety.ReportTarget)
        case block(ContentSafety.Author)
    }

    /// Everything worth showing. A post with no author, no dish, no words
    /// and no photo is not a post — see `TablePost.isBlank`. Filtered here
    /// rather than in the `@Query` so the rule is stated once and every
    /// reader of the feed gets it, counts included.
    private var realPosts: [TablePost] { posts.filter(\.isUserContent) }

    /// Blocking is a private lens over the feed, never a mutation of the
    /// shared CloudKit record. Keep `realPosts` as the complete local mirror
    /// for publishing and reconciliation; only this display list is filtered.
    private var visiblePosts: [TablePost] {
        realPosts.filter {
            !contentSafety.isBlocked(authorID: $0.authorID, authorName: $0.authorName)
        }
    }

    private var seatCount: Int {
        // Who can plate: head/joined seats plus Table guest authors —
        // same denominator the Chef's kiss uses (TableKiss.seating).
        TableKiss.seating(
            members: members,
            dishAuthors: realPosts.filter { $0.kind == "dish" }.map(\.authorName)
        )
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
    /// connection leaves `isPublished` false. The record name is minted at
    /// birth so reactions have a stable key; publication therefore needs its
    /// own truth rather than treating an identifier as delivery evidence.
    ///
    /// This is that attempt. It runs on pull/first appearance and when a
    /// known available path returns to the foreground Table. It is
    /// idempotent: `publish` reuses a name it is
    /// given, so a post that turns out to have gone after all is overwritten
    /// with itself rather than duplicated.
    private func publishBacklog() async {
        guard !PlatedApp.usesPreviewContainer,
              publicationConnection != .unavailable else { return }
        guard backlogPass.begin() else { return }
        defer {
            let followUp = backlogPass.finish()
            if followUp, backlogRecovery.permitsRetry {
                Task { await publishBacklog() }
            }
        }
        let initialAccount = TableIdentity.cached
        let account: String
        if initialAccount.hasPrefix("local-") {
            // Resolve before selecting work: exact-placeholder migration makes
            // these local posts owned by the confirmed account. Pin that real
            // account for the whole pass so a later Apple ID switch still aborts.
            guard let confirmed = await TableIdentity.confirmAndReattribute(in: context),
                  TablePostPublication.mayContinue(from: initialAccount, as: confirmed),
                  TableIdentity.cached == confirmed else { return }
            account = confirmed
        } else {
            account = initialAccount
        }
        let stranded = realPosts.filter { !$0.isRemote && !$0.isPublished && isMine($0) }
        let hostName = members.first(where: \.isOwner)?.name ?? ""
        var sent = false
        for post in stranded {
            guard !Task.isCancelled, TableIdentity.cached == account,
                  publicationConnection != .unavailable else { break }
            // Another writer can finish while the previous record is awaiting
            // CloudKit. Recheck the row and current ownership before proceeding.
            guard !post.isDeleted, !post.isRemote, !post.isPublished, isMine(post) else { continue }
            // Composer/retry work may already be sending this exact record.
            // Keep the current attempt and its fixed audience; don't stack
            // another request just because the path changed.
            if publicationState(post) == .sending {
                publication.requestRecovery(for: publicationKey(post))
                continue
            }
            if let name = await TableShare.publish(post, hostName: hostName) {
                post.shareRecordName = name
                post.isPublished = true
                sent = true
            }
        }
        if sent { Persist.save(context, "publish backlog") }
    }

    /// Completion notifications may arrive while another recovered post is
    /// awaiting CloudKit. Coalesce them into the running drain, rather than
    /// letting a changed SwiftUI task ID cancel that valid write.
    private func scheduleDeferredPublications() {
        guard backlogRecovery.permitsRetry else {
            cancelDeferredPublications()
            publication.discardRecoveries()
            return
        }
        let account = TableIdentity.cached
        if let work = deferredRecoveryWork, work.account != account {
            cancelDeferredPublications()
        }
        guard deferredRecoveryWork == nil else { return }
        let id = UUID()
        let task = Task { @MainActor in
            await resumeDeferredPublications()
            // A cancelled old run must not clear its replacement's handle.
            if deferredRecoveryWork?.id == id { deferredRecoveryWork = nil }
        }
        deferredRecoveryWork = DeferredRecoveryWork(id: id, account: account, task: task)
    }

    private func cancelDeferredPublications() {
        deferredRecoveryWork?.task.cancel()
        deferredRecoveryWork = nil
    }

    private func resumeDeferredPublications() async {
        let account = TableIdentity.cached
        guard backlogRecovery.permitsRetry else {
            publication.discardRecoveries()
            return
        }
        let hostName = members.first(where: \.isOwner)?.name ?? ""
        var sent = false
        while !Task.isCancelled, TableIdentity.cached == account, backlogRecovery.permitsRetry {
            guard let key = publication.takeNextReadyRecovery(account: account) else { break }
            guard let post = realPosts.first(where: { publicationKey($0) == key }),
                  !post.isDeleted, !post.isRemote, !post.isPublished, isMine(post) else { continue }
            if publicationState(post) == .sending {
                // Another independently requested write started after this
                // request became ready. Keep the same one-shot intent waiting.
                publication.requestRecovery(for: key)
                continue
            }
            if let name = await TableShare.publish(post, hostName: hostName) {
                post.shareRecordName = name
                post.isPublished = true
                sent = true
            }
        }
        if sent { Persist.save(context, "recover deferred table posts") }
    }

    private func refreshFeed() async {
        // A review pull must not drain durable work or open the real store.
        // Keep its chosen loading/error/waiting fixture deterministic instead.
        if PlatedApp.usesPreviewContainer {
            switch reviewState {
            case .standard, .empty: reach = .reached
            case .loading: reach = .looking
            case .error: reach = .unreachable
            }
            return
        }
        Persist.save(context)
        await publishBacklog()
        // Everything tapped since the last pull, including everything
        // tapped with no signal at all. Before the posts, so a plate on a
        // dish somebody else is about to edit does not lose a round trip.
        // The outbox holds a comment's NAME, not its text: a queue that
        // carries a copy of what somebody wrote is a second place for it to
        // be wrong. It asks for the row back here, where there is a context
        // to ask with.
        TableOutbox.shared.resolveNote = { [context] name in
            let all = (try? context.fetch(FetchDescriptor<TableComment>())) ?? []
            return all.first { $0.shareRecordName == name }
        }
        await TableOutbox.shared.drain(
            authorName: members.me?.name ?? ""
        )
        // Two different pipes, pulled together because the user pulled once.
        // The mirror carries this household's own devices; TableShare
        // carries everybody else's table. Neither knows about the other.
        // Through the same door as a push, one at a time. Merging here
        // alone burned the change token, so anything the feed pulled itself
        // never reached the bell and could never be replayed for it: after
        // a force-quit or a night in Low Power Mode the bell asserted
        // nothing happened.
        async let pulled: Void = TablePull.pull(reason: "refresh")
        let outcome = await CloudSync.waitForImport()
        await pulled
        // Let go mid-pull and there is nothing to confirm — the tick used
        // to fire anyway, because `try?` around the sleep swallowed the
        // cancellation and left the call site unable to tell an abandoned
        // refresh from a finished one.
        guard !Task.isCancelled else { return }
        switch outcome {
        case .arrived, .quiet:
            reach = TablePull.lastReadSucceeded ? .reached : .unreachable
            if TablePull.lastReadSucceeded { Haptic.tap() } else { Haptic.warn() }
        case .failed:
            reach = .unreachable
            Haptic.warn()
        }
    }

    // MARK: The three empty tables

    /// Still asking. Only ever seen on a cold launch with nothing cached,
    /// and only for as long as the ask takes.
    private var lookingForPosts: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
                .tint(Color.inkFaint)
            Text("Checking the Table…")
                .plType(.footnote, .semibold)
                .foregroundStyle(Color.inkSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking the Table for new posts")
    }

    /// Asked, and got an answer: nobody has posted. This is the only one of
    /// the three that may say so, because it is the only one that knows.
    private var nothingPlatedYet: some View {
        VStack(spacing: 10) {
            PlateReactionGlyph(filled: false)
                .accessibilityHidden(true)
            Text(scope == .household ? "No household posts yet" : "Your Table is ready")
                .plType(.body, .bold)
                .foregroundStyle(Color.ink)
            Text(scope == .household
                 ? "Share a photo, a food find, or a question to get the conversation going."
                 : "Share what you cooked, ask what sounds good, or invite someone you trust.")
                .plType(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
            Button {
                Haptic.tap()
                composerShown = true
            } label: {
                Text("Share something")
                    .plType(.body, .bold)
                    .plActionLabel()
                    .foregroundStyle(Color.onPrimary)
                    .padding(.horizontal, Spacing.page)
                    .frame(minHeight: 44)
                    .background(Color.primaryAction, in: Radius.shape(Radius.chip))
            }
            .buttonStyle(.pressable)
            .padding(.top, 4)

            if scope == .everyone && seatCount <= 1 {
                Button("Invite someone") {
                    Haptic.tap()
                    seatsPresented = true
                }
                .plType(.footnote, .bold)
                .plActionLabel()
                .foregroundStyle(Color.ink)
                .plTapTarget()
                .buttonStyle(.pressable)
            }

            Label("Invite only · never public", systemImage: "lock.fill")
                .plType(.micro, .semibold)
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 2)
        }
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
                .accessibilityHidden(true)
            Text("Couldn't refresh the Table")
                .plType(.body, .bold)
                .foregroundStyle(Color.ink)
            Text("Your posts are still safe on this iPhone. Check your connection and try again.")
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
                    .plActionLabel()
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, Spacing.page)
                    .frame(minHeight: 44)
                    .overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline, lineWidth: 1.5))
                    .contentShape(Radius.shape(Radius.chip))
            }
            .buttonStyle(.pressable)
            .padding(.top, 4)
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
            .filter { $0.first?.isLetter == true }
            .prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    /// The avatar is decorative inside this profile door. Give VoiceOver the
    /// same byline and delivery context a sighted reader gets, without making
    /// it spell the monogram before the person's name.
    private func authorAccessibilityLabel(_ post: TablePost) -> String {
        var parts = [post.authorName, postWhen(post.createdAt)]
        if post.isRemote { parts.append("from another table") }
        if NewsPreferences.isMuted(post: post.shareRecordName) { parts.append("muted") }
        return parts.joined(separator: ", ")
    }

    private func postAccessibilityName(_ post: TablePost) -> String {
        if !post.dishTitle.isEmpty { return post.dishTitle }
        return post.kind == "ask" ? "question by \(post.authorName)" : "post by \(post.authorName)"
    }

    /// True once "Everyone" and "Household" could return different lists —
    /// that is, once the table holds a post by somebody who is not in the
    /// house. Derived rather than remembered, so it goes away again if that
    /// post does.
    private var scopeIsMeaningful: Bool {
        if reviewState != .standard { return false }
        return visiblePosts.contains { !belongsToHousehold($0) }
    }

    @ViewBuilder
    private var currentEmptyState: some View {
        switch reach {
        case .looking: lookingForPosts
        case .unreachable: cannotReachTable
        case .reached: nothingPlatedYet
        }
    }

    private var shownPosts: [TablePost] {
        if reviewState != .standard { return [] }
        guard scope == .household else { return visiblePosts }
        return visiblePosts.filter(belongsToHousehold)
    }

    /// Household identity has two valid roads: the participant id learned
    /// from the share and the user record name stored on the household row.
    /// The organizer is intentionally absent from `share.participants`, so
    /// using participant ids alone filtered the host out of their own home.
    private var householdIdentityIDs: Set<String> {
        var ids = Set(members.flatMap { member in
            [member.participantID, member.userRecordName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        })
        if case .member(let owner) = HouseholdShare.membership, !owner.isEmpty {
            ids.insert(owner)
        }
        let me = TableIdentity.cached
        if !me.isEmpty && !me.hasPrefix("local-") { ids.insert(me) }
        return ids
    }

    private func belongsToHousehold(_ post: TablePost) -> Bool {
        let ids = householdIdentityIDs
        let names = Set(members.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        // Accepted CloudKit identity is authoritative. A display-name
        // match must never override a known person's different identity.
        if !post.authorID.isEmpty && !post.authorID.hasPrefix("local-") {
            return ids.contains(post.authorID)
        }
        // Older local posts predate author IDs. Retain the original
        // short-name matching until those records acquire an identity.
        let fullName = post.authorName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return names.contains(fullName) || names.contains(post.firstName.lowercased())
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 0) {
                header.id("table-top")
                    .padding(.horizontal, Spacing.page)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                tableContextBar
                    .padding(.horizontal, Spacing.page)
                    .padding(.bottom, scopeIsMeaningful ? 10 : 12)

                if scopeIsMeaningful {
                    scopePicker
                        .padding(.horizontal, Spacing.page)
                        // Together with the post's 16pt top inset, this
                        // preserves the approved 19pt filter-to-author gap.
                        .padding(.bottom, 3)
                        .transition(.plUnfold)
                }

                if reach == .unreachable, !shownPosts.isEmpty {
                    refreshProblemBar
                        .padding(.horizontal, Spacing.page)
                        .padding(.bottom, 10)
                        .transition(.plUnfold)
                }

                        Color.clear.frame(height: 0).id("table-content")
                        ForEach(Array(shownPosts.enumerated()),
                                id: \.element.persistentModelID) { index, post in
                            // Before each card except the very first thing in
                            // the list, never after the last. A separator marks
                            // the boundary BETWEEN two rows; trailing the final
                            // one, the feed ended on a hairline with nothing
                            // under it but the floating bar's inset.
                            if index > 0 {
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
                            currentEmptyState
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .padding(.bottom, Layout.floatingChromeInset)
                        }
                    }
                    // An empty table is one screen and does not scroll; the
                    // clearance is for a list that runs under the bar.
                    .padding(.bottom, shownPosts.isEmpty ? 0 : Layout.floatingChromeInset)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("table-feed")
                .onChange(of: tabPop) { _, request in
                    guard request.tab == .table else { return }
                    withAnimation(.plSnap) { scroll.scrollTo("table-top", anchor: .top) }
                }
                .refreshable { await refreshFeed() }
                .task {
                    guard !hasLooked else { return }
                    hasLooked = true
                    switch reviewState {
                    case .empty:
                        reach = .reached
                        return
                    case .loading:
                        reach = .looking
                        return
                    case .error:
                        reach = .unreachable
                        return
                    case .standard:
                        break
                    }
                    // Seed the ledger from the fields that used to hold
                    // this, once, before anything reads it.
                    TableReactions.backfill(posts, context: context)
                    // Ask CloudKit who we are, through the one door: a
                    // placeholder minted while offline is re-attributed the
                    // moment a real id arrives, so nothing tapped on a plane
                    // is orphaned, and a real id that became a different
                    // real id is an account switch, not a rename. The copy
                    // that used to live here moved the ledger and the outbox
                    // and left the household rows behind.
                    //
                    // Design Review runs on an in-memory household. Crossing
                    // this boundary would replace its local identity with the
                    // simulator's real CloudKit identity while the shell is
                    // deciding who owns the head seat, creating a duplicate
                    // organizer in the very fixture meant to audit trust.
                    if PlatedApp.usesPreviewContainer {
                        reach = .reached
                        return
                    }
                    // Begin observing immediately, so a slow identity request
                    // doesn't hide a known outage. Recovery waits for this
                    // initial identity check before starting another writer.
                    network = NetworkAvailability.shared
                    _ = await TableIdentity.confirmAndReattribute(in: context)
                    initialIdentityChecked = true
                    await refreshFeed()
                }
                // A seat accepted from Messages while the Table is already
                // open would otherwise sit invisible until the next pull.
                // A push says something changed; the fetch says what. The
                // app never renders anything from a notification payload —
                // a silent push carries no truth, only a reason to look.
                .onReceive(NotificationCenter.default.publisher(
                    for: ShareAcceptor.didChangeRemotely
                )) { _ in
                    // The central reader has already merged the change.
                    // Starting another pull here creates a refresh loop and
                    // plays pull-to-refresh haptics for background activity.
                    reach = TablePull.lastReadSucceeded ? .reached : .unreachable
                }
                // A notice about one dish opens that dish. The request is
                // parked by the shell; the feed collects it here, or on
                // appear if the Table was not on screen when it was tapped.
                .onReceive(NotificationCenter.default.publisher(for: LinkRelay.postRequested)) { _ in
                    openRequestedPost()
                }
                .onChange(of: scopeIsMeaningful) { _, meaningful in
                    if !meaningful { scope = .everyone }
                }
            }
            .background(Color.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .plSwipeBack()
            .navigationDestination(item: $threadPost) { post in
                PostThreadView(post: post, startWriting: threadStartsWriting, targetComment: threadTargetComment) { beginSave($0) }
                    .navigationTransition(.zoom(sourceID: post.persistentModelID, in: zoom))
            }
            .navigationDestination(item: $personShown) { person in
                PersonProfileView(personName: person.name, colorHex: person.colorHex, memberID: person.memberID, authorID: person.authorID)
                    .navigationTransition(.zoom(sourceID: personDoor, in: zoom))
            }
            .navigationDestination(item: $pushed) { destination in
                switch destination {
                case .activity: NotificationsView(homeTab: .table)
                }
            }
        }
        // Two `.sheet` modifiers on one view is undefined — see CLAUDE.md.
        // Composer lived on the stack's content before; same sheet content,
        // one presentation owner with seats / edit / save.
        .sheet(item: feedSheet) { destination in
            switch destination {
            case .composer:
                TableComposerSheet()
            case .seats:
                TableSeatsSheet()
            case .editPost(let post):
                PostEditSheet(post: post)
            case .editSave(let post):
                RecipeEditorView(prefill: (
                    title: post.dishTitle.isEmpty ? "\(post.firstName)'s dish" : post.dishTitle,
                    summary: post.caption,
                    photo: post.photoData,
                    originID: post.originKey
                )) { _ in
                    finishSave(post)
                }
            }
        }
        .confirmationDialog(
            actionDialogTitle,
            isPresented: Binding(
                get: { pendingDelete != nil || safetyDialog != nil },
                set: {
                    if !$0 {
                        pendingDelete = nil
                        safetyDialog = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let post = pendingDelete {
                Button("Delete", role: .destructive) { deletePost(post) }
                Button("Cancel", role: .cancel) {}
            } else if let safetyDialog {
                switch safetyDialog {
                case .report(let target):
                    ForEach(ContentSafety.ReportReason.allCases) { reason in
                        Button(reason.rawValue) { report(target, because: reason) }
                    }
                    Button("Cancel", role: .cancel) {}
                case .block(let author):
                    Button("Block \(author.label)", role: .destructive) {
                        block(author)
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        } message: {
            Text(actionDialogMessage)
        }
        // See TabPopRequest: tapping Table while a thread or a profile is
        // pushed returns to the feed.
        .onChange(of: tabPop) { _, request in
            guard request.tab == .table else { return }
            threadPost = nil
            personShown = nil
            pushed = nil
        }
        .task(id: backlogRecovery) {
            guard backlogRecovery.permitsRetry else { return }
            await publishBacklog()
        }
        .task(id: deferredRecoveryTrigger) {
            scheduleDeferredPublications()
        }
        .onChange(of: activeAppTab) { _, _ in updateFeedPresence() }
        .onChange(of: threadPost) { _, _ in updateFeedPresence() }
        .onChange(of: personShown) { _, _ in updateFeedPresence() }
        .onChange(of: pushed) { _, _ in updateFeedPresence() }
        .onAppear {
            // While the feed is in front, a banner about a new dish would
            // point at what is already on screen. See NotificationRouter.
            openRequestedPost()
            updateFeedPresence()
            #if DEBUG
            if LaunchFlags.consume("-plated-open-seats") {
                seatsPresented = true
            }
            if LaunchFlags.consume("-plated-open-thread") {
                threadPost = visiblePosts.first { $0.shareRecordName == "post-review-comment-reactions" }
                    ?? visiblePosts.first { $0.kind == "dish" }
            }
            #endif
        }
        .onDisappear {
            cancelDeferredPublications()
            publication.discardRecoveries()
            if Presence.shared.feedVisible { Presence.shared.feedVisible = false }
        }
        .overlay(alignment: .bottom) {
            if let toast = savedToast {
                Text(toast)
                    .plType(.footnote, .bold)
                    .foregroundStyle(Color.canvas)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .background(Color.ink, in: Radius.shape(Radius.chip))
                    // The perch occupies 84…134; a hand-typed 100 put a long
                    // toast underneath it. The last bottom inset on the
                    // branch that hadn't gone through the token family the
                    // rest of this class was built to fix.
                    .padding(.bottom, Layout.floatingChromeInset)
                    .transition(.plRise)
            }
        }
    }

    private func updateFeedPresence() {
        Presence.shared.feedVisible = activeAppTab == .table
            && threadPost == nil && personShown == nil && pushed == nil
    }

    private var actionDialogTitle: String {
        if let post = pendingDelete {
            return post.dishTitle.isEmpty ? "Delete this post?" : "Delete \(post.dishTitle)?"
        }
        switch safetyDialog {
        case .report(let target):
            return "Why are you reporting this \(target.kind.rawValue)?"
        case .block(let author):
            return "Block \(author.label)?"
        case nil:
            return ""
        }
    }

    private var actionDialogMessage: String {
        if pendingDelete != nil {
            // "Everyone" is now a promise the code keeps. It used to delete
            // the local row only, and the post came back on the next pull.
            return "It comes off the table for everyone. The photo and comments go too."
        }
        switch safetyDialog {
        case .report:
            return "Plated opens a private email with the reason and opaque references only. The post, comments and photos are not included."
        case .block:
            return "Their posts and comments disappear on this device. They are not notified, and you can unblock them from People."
        case nil:
            return ""
        }
    }

    private func report(_ target: ContentSafety.ReportTarget, because reason: ContentSafety.ReportReason) {
        safetyDialog = nil
        guard let url = contentSafety.reportURL(for: target, reason: reason) else {
            Haptic.warn()
            showToast("Couldn't prepare the report email")
            return
        }
        Haptic.tap()
        openURL(url)
    }

    private func block(_ author: ContentSafety.Author) {
        safetyDialog = nil
        guard contentSafety.block(
            author,
            currentIdentityIDs: currentIdentityIDs,
            currentDisplayNames: currentDisplayNames
        ) else { return }
        WidgetBridge.publish(from: context)
        AppBadge.sync(context)
        let message = "\(author.firstName)'s posts and comments are hidden"
        showToast(message)
    }

    private func author(for post: TablePost) -> ContentSafety.Author {
        ContentSafety.Author(identity: post.authorID, displayName: post.authorName)
    }

    private func canBlock(_ post: TablePost) -> Bool {
        contentSafety.canBlock(
            author(for: post),
            currentIdentityIDs: currentIdentityIDs,
            currentDisplayNames: currentDisplayNames
        )
    }

    private func canReport(_ post: TablePost) -> Bool {
        contentSafety.canReport(
            author(for: post),
            currentIdentityIDs: currentIdentityIDs,
            knownToBeSelf: isMine(post)
        )
    }

    private func visibleComments(for post: TablePost) -> [TableComment] {
        post.sortedComments.filter {
            $0.deletedAt == nil && !contentSafety.isBlocked(authorID: $0.authorID, authorName: $0.authorName)
        }
    }

    private enum FeedSheet: Identifiable {
        case composer, seats, editPost(TablePost), editSave(TablePost)
        var id: String {
            switch self {
            case .composer: "composer"
            case .seats: "seats"
            case .editPost(let post): "edit-post-\(post.persistentModelID)"
            case .editSave(let post): "edit-save-\(post.persistentModelID)"
            }
        }
    }
    private var feedSheet: Binding<FeedSheet?> {
        Binding(
            get: {
                if composerShown { return .composer }
                if seatsPresented { return .seats }
                if let editingPost { return .editPost(editingPost) }
                if let editingSave { return .editSave(editingSave) }
                return nil
            },
            set: {
                if $0 == nil {
                    composerShown = false
                    seatsPresented = false
                    editingPost = nil
                    editingSave = nil
                }
            }
        )
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        PlatedMasthead(title: "The Table", titleBelowTools: true, compact: true) {
            HStack(spacing: 8) {
                ActivityBellButton(size: 44, accessibilityID: "table-notifications-bell") { pushed = .activity }
                AccountButton()
            }
        }
    }

    /// The privacy promise and its audience are one compact door. It stays
    /// above the feed because trust must be visible, but it may not consume
    /// the first screen before a single person or dish appears.
    private var tableContextBar: some View {
        Button {
            Haptic.tap()
            seatsPresented = true
        } label: {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Label("Private to your Table", systemImage: "lock.fill")
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("People")
                    .plType(.footnote, .semibold)
                    .foregroundStyle(Color.accentText)
                    .frame(minHeight: 44)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Private to your Table. People and invitations.")
        .accessibilityHint("Shows who can see posts")
        .accessibilityIdentifier("table-people")
    }

    private var refreshProblemBar: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    refreshProblemMessage
                    refreshRetryButton
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 10) {
                    refreshProblemMessage
                    refreshRetryButton
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(Color.fill, in: Radius.shape(Radius.chip))
    }

    private var refreshProblemMessage: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.inkSecondary)
                .accessibilityHidden(true)
            Text("Couldn't refresh. Showing what's on this iPhone.")
                .plType(.caption, .semibold)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var refreshRetryButton: some View {
        Button("Retry") {
            Haptic.tap()
            reach = .looking
            Task { await refreshFeed() }
        }
            .plType(.caption, .bold)
            .plActionLabel()
            .foregroundStyle(Color.ink)
            .plTapTarget()
    }

    /// All joined tables or just the household — a quiet two-way scope.
    /// The raised pill SLIDES between options (one shared identity), it
    /// doesn't blink out and reappear.
    private var scopePicker: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 20))
        return layout {
            ForEach(FeedScope.allCases, id: \.self) { value in
                Button { Haptic.select(); scope = value } label: {
                    Text(value.rawValue).plType(.caption, scope == value ? .semibold : .regular)
                        .foregroundStyle(scope == value ? Color.ink : Color.inkSecondary)
                        .frame(minHeight: 44)
                        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(scope == value ? Color.olive : Color.clear).frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(scope == value ? .isSelected : [])
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .overlay(alignment: .bottom) { Color.hairline.frame(height: 0.5) }
        .accessibilityElement(children: .contain)
    }

    // MARK: Cards

    private func postCard(_ post: TablePost) -> some View {
        let comments = visibleComments(for: post)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    openProfile(post)
                } label: {
                    HStack(spacing: 10) {
                        AvatarCircle(initials: post.initials, tone: PersonTone.from(hex: post.authorColorHex), size: 36,
                                     photo: members.photo(forAuthor: post.authorName, authorID: post.authorID))
                            .matchedTransitionSource(id: ZoomID.author(post.persistentModelID), in: zoom)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(post.authorName)
                                .plName()
                                .plType(.body, .bold)
                                .foregroundStyle(Color.ink)
                            HStack(spacing: 5) {
                                Text(postWhen(post.createdAt))
                                    .plType(.caption)
                                    .foregroundStyle(Color.inkSecondary)
                                // Whose table this came from, said once and
                                // quietly. No badge, no tint: a guest's dish
                                // is not a lesser dish, it just isn't from
                                // this house, and the feed says so without
                                // ranking it.
                                if post.isRemote {
                                    Text("· another table")
                                        .plType(.caption)
                                        .foregroundStyle(Color.inkSecondary)
                                }
                                // The state, not a badge: a muted dish says
                                // so where its time is, the way a muted
                                // conversation does in Messages.
                                if muteVersion >= 0, NewsPreferences.isMuted(post: post.shareRecordName) {
                                    Image(systemName: "bell.slash")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.inkSecondary)
                                        .accessibilityLabel("Muted")
                                }
                            }
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(authorAccessibilityLabel(post))
                .accessibilityHint("Shows \(post.firstName)'s profile")
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
                    postMenu(post, canSave: post.kind == "dish")
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                        .plTapTarget()
                }
                .accessibilityLabel("More options for \(postAccessibilityName(post))")
            }
            .padding(.bottom, 10)

            ZStack(alignment: .topTrailing) {
                if let data = post.photoData, let image = UIImage(data: data) {
                    // The photo is the door to the thread.
                    Button {
                        openThread(post)
                    } label: {
                        PhotoWell(image: image, clamped: true, maximumHeight: 288, cornerRadius: 10)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(
                        post.dishTitle.isEmpty
                            ? "Open post by \(post.authorName)"
                            : "Open \(post.dishTitle) by \(post.authorName)"
                    )
                    .accessibilityHint("Opens the post")
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
                if post.hasChefsKiss(seats: seatCount) {
                    chefsKissPill
                        .offset(x: 6, y: -10)
                        // Appears; does not launch. 0.01 threw it in from
                        // a point, which is the fly-in note again.
                        .transition(.plArrive)
                }
            }

            // Media gives the actions context; text-only posts introduce their words first.
            if post.photoData != nil {
                postActions(post).animation(.plSnap, value: isSaved(post))
            }
            Button {
                openThread(post)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    if !post.caption.isEmpty || !post.dishTitle.isEmpty {
                        captionText(post)
                            // Three lines, then "more". Unbounded, a twelve
                            // line caption pushed the plate, the comments
                            // and Save clean off the bottom of the card.
                            // Three rather than Instagram's one: these are
                            // sentences about food from people you know, and
                            // clipping at one would make the expander a
                            // required tap on nearly every post.
                            .lineLimit(expandedCaptions.contains(post.persistentModelID) ? nil : 3)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
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
                        .plActionLabel()
                        .foregroundStyle(Color.inkSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
            if post.photoData == nil {
                postActions(post)
                    .padding(.top, 4)
                    .animation(.plSnap, value: isSaved(post))
            }
            publicationStatus(post)
            // Keep the feed compact; the complete, reactive conversation is
            // one explicit action away instead of repeating reply rows here.
            Button {
                openThread(post, writing: comments.isEmpty)
            } label: {
                Text(comments.isEmpty ? "Add a comment" : "View \(comments.count.things("comment"))")
                    .plType(.caption, .semibold)
                    .plActionLabel(0.72)
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("table-comments-" + post.shareRecordName)
            .padding(.top, 2)
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .animation(.plPop, value: post.hasChefsKiss(seats: seatCount))
        .contextMenu { postMenu(post, canSave: post.kind == "dish") }
    }

    private func publicationKey(_ post: TablePost) -> TablePostPublication.Key {
        .init(account: TableIdentity.cached, owner: post.shareZoneOwner,
              recordName: post.shareRecordName, isPublished: post.isPublished)
    }

    private func publicationState(_ post: TablePost) -> TablePostPublication.Status {
        publication.status(for: publicationKey(post),
                           isPublished: post.isPublished, connection: publicationConnection)
    }

    @ViewBuilder
    private func publicationStatus(_ post: TablePost) -> some View {
        if !post.isRemote && isMine(post) {
            let state = publicationState(post)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Label(state.label, systemImage: state.symbol)
                    .plType(.caption)
                    .foregroundStyle(state == .failed ? Color.dangerText : Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("post-publication-\(post.shareRecordName)")
                if state == .failed {
                    Button { retryPublication(post) } label: {
                        Text("Retry").plType(.caption, .semibold).foregroundStyle(Color.accentText)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Retry sharing \(postAccessibilityName(post))")
                    .accessibilityIdentifier("post-publication-retry-" + post.shareRecordName)
                }
            }
            .padding(.top, 7)
        }
    }

    private func retryPublication(_ post: TablePost) {
        // The fixture's Retry is safe to exercise without publishing sample
        // content or changing its deliberately injected publication state.
        guard !PlatedApp.usesPreviewContainer,
              publicationState(post) != .sending else { return }
        Task {
            if let name = await TableShare.publish(post, hostName: members.me?.name ?? "") {
                post.shareRecordName = name
                Persist.save(context, "retry table post")
            } else {
                showToast("Couldn’t share. Your post is saved on this device.")
            }
        }
    }

    @ViewBuilder
    private func postMenu(_ post: TablePost, canSave: Bool) -> some View {
        if !post.isRemote && !post.isPublished && isMine(post) {
            Button(publicationState(post) == .failed ? "Retry sharing" : "Share post", systemImage: "arrow.clockwise") {
                retryPublication(post)
            }.disabled(publicationState(post) == .sending)
        }

        Button {
            openThread(post)
        } label: {
            Label("Comments", systemImage: "bubble.right")
        }
        // Silent to everyone else, the way Messages does it. Replies to
        // you still get through; the toast says so, because a mute that
        // quietly let something past would read as broken.
        if !post.shareRecordName.isEmpty {
            let muted = NewsPreferences.isMuted(post: post.shareRecordName)
            Button {
                NewsPreferences.setMuted(post: post.shareRecordName, !muted)
                muteVersion += 1
                showToast(muted ? "Unmuted" : "Muted. Replies to you still get through")
            } label: {
                Label(muted ? "Unmute this post" : "Mute this post", systemImage: muted ? "bell" : "bell.slash")
            }
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
        let reportAllowed = canReport(post)
        let blockAllowed = canBlock(post)
        if reportAllowed || blockAllowed {
            Section {
                if reportAllowed {
                    Button {
                        safetyDialog = .report(.post(post))
                    } label: {
                        Label("Report post", systemImage: "exclamationmark.bubble")
                    }
                }
                if blockAllowed {
                    Button(role: .destructive) {
                        safetyDialog = .block(author(for: post))
                    } label: {
                        Label("Block \(post.firstName)", systemImage: "person.slash")
                    }
                }
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

    private func isMine(_ post: TablePost) -> Bool {
        TableMutationAuthorization.owns(
            post: post,
            identityIDs: currentIdentityIDs,
            displayNames: currentDisplayNames
        )
    }

    private var currentIdentityIDs: [String] {
        [TableIdentity.cached, members.me?.participantID, members.me?.userRecordName]
            .compactMap { $0 }
    }

    private var currentDisplayNames: [String] {
        let typed = UserDefaults.standard.string(forKey: "userFirstName")
        return [members.me?.name, typed].compactMap { $0 }
    }

    private var reactionAuthorName: String {
        members.me?.name
            ?? UserDefaults.standard.string(forKey: "userFirstName")
            ?? ""
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
        // The menu was authorized when it was drawn; the account may have
        // changed before confirmation. Never let a stale dialog cross the
        // destructive boundary.
        guard isMine(post) else {
            pendingDelete = nil
            return
        }
        let recordName = post.shareRecordName
        let zoneOwner = post.shareZoneOwner
        pendingDelete = nil
        Task {
            guard await TableShare.retract(recordName: recordName, zoneOwner: zoneOwner) else {
                Haptic.warn()
                showToast("Couldn't reach iCloud. The post is still on the table.")
                return
            }
            // CloudKit awaited outside the UI transaction. Re-check before
            // touching the local store for the same stale-account reason.
            guard isMine(post) else { return }
            Haptic.plate()
            TableReactions.forgetComments(Set((post.comments ?? []).map(\.shareRecordName)))
            withAnimation(.plSnap) { context.delete(post) }
            Persist.save(context, "delete table post")
        }
    }

    private func askCard(_ post: TablePost) -> some View {
        let comments = visibleComments(for: post)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    openProfile(post)
                } label: {
                    HStack(spacing: 10) {
                        AvatarCircle(initials: post.initials, tone: PersonTone.from(hex: post.authorColorHex), size: 36,
                                     photo: members.photo(forAuthor: post.authorName, authorID: post.authorID))
                            .matchedTransitionSource(id: ZoomID.author(post.persistentModelID), in: zoom)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(post.authorName)
                                .plName()
                                .plType(.body, .bold)
                                .foregroundStyle(Color.ink)
                            HStack(spacing: 5) {
                                Text(postWhen(post.createdAt))
                                    .plType(.caption)
                                    .foregroundStyle(Color.inkSecondary)
                                // Whose table this came from, said once and
                                // quietly. No badge, no tint: a guest's dish
                                // is not a lesser dish, it just isn't from
                                // this house, and the feed says so without
                                // ranking it.
                                if post.isRemote {
                                    Text("· another table")
                                        .plType(.caption)
                                        .foregroundStyle(Color.inkSecondary)
                                }
                                // The state, not a badge: a muted dish says
                                // so where its time is, the way a muted
                                // conversation does in Messages.
                                if muteVersion >= 0, NewsPreferences.isMuted(post: post.shareRecordName) {
                                    Image(systemName: "bell.slash")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.inkSecondary)
                                        .accessibilityLabel("Muted")
                                }
                            }
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(authorAccessibilityLabel(post))
                .accessibilityHint("Shows \(post.firstName)'s profile")
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
                .accessibilityLabel("More options for \(postAccessibilityName(post))")
            }
            Button {
                openThread(post)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    if let data = post.photoData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: 260).accessibilityLabel("Post photo")
                    }
                    if !post.dishTitle.isEmpty {
                        Text(post.dishTitle).plType(.heading).foregroundStyle(Color.ink)
                    }
                    Text(post.caption)
                        .plType(.body)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    if post.hasPoll {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 11, weight: .bold))
                            Text("\(post.pollOptions.count.things("choice")) · \(post.totalPollVotes.things("vote"))")
                                .plType(.micro)
                        }
                        .foregroundStyle(Color.completion)
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
            publicationStatus(post)
            ForEach(comments.suffix(2), id: \.persistentModelID) { comment in
                commentLine(comment)
            }
            Button {
                openThread(post, writing: comments.count <= 2)
            } label: {
                // Questions can be broader than dinner suggestions. "Reply"
                // stays true for a recipe link, a vote explanation, or a
                // simple answer.
                Text(comments.count > 2
                     ? "See all \(comments.count) replies"
                     : "Add a reply")
                    .plType(.caption, .semibold)
                    .plActionLabel(0.72)
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, Spacing.page)
        .padding(.vertical, 16)
        .contextMenu { postMenu(post, canSave: false) }
    }

    private var chefsKissPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.amber)
            Text("Chef's kiss")
                .plType(.footnote, .bold)
                .foregroundStyle(Color.ink)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(Color.canvas, in: Radius.shape(Radius.chip))
        .overlay(Radius.shape(Radius.chip).strokeBorder(Color.navHairline))
        .plCardShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chef's kiss")
    }

    /// Three useful controls cannot remain one horizontal sentence once each
    /// word is several times its default size. Give every action the full row
    /// at accessibility sizes; the compact social row remains unchanged.
    @ViewBuilder
    private func postActions(_ post: TablePost) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                plateButton(post)
                    .frame(maxWidth: .infinity, alignment: .leading)
                commentsButton(post)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if post.kind == "dish" {
                    saveButton(post).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            HStack(spacing: 14) {
                plateButton(post)
                commentsButton(post)
                Spacer()
                if post.kind == "dish" { saveButton(post) }
            }
        }
    }

    private func commentsButton(_ post: TablePost) -> some View {
        let comments = visibleComments(for: post)
        return Button {
            openThread(post)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "bubble.right")
                    .font(.system(size: 22, weight: .regular))
                if typeSize.isAccessibilitySize {
                    Text(comments.isEmpty
                         ? "Comments"
                         : comments.count.things("comment"))
                        .plType(.footnote, .bold)
                        .plActionLabel()
                } else if !comments.isEmpty {
                    Text("\(comments.count)")
                        .plType(.caption)
                }
            }
            .foregroundStyle(Color.inkSecondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(comments.isEmpty
                            ? "Comments"
                            : comments.count.things("comment"))
        .accessibilityHint("Opens the conversation")
    }

    private func saveButton(_ post: TablePost) -> some View {
        let saved = isSaved(post)
        return Button {
            beginSave(post)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 22, weight: .regular))
                    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
                if typeSize.isAccessibilitySize {
                    Text(saved ? "In cookbook" : "Save to cookbook")
                        .plType(.footnote).plActionLabel()
                }
            }
            .foregroundStyle(Color.inkSecondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(saved ? "Saved to your cookbook" : "Save to cookbook")
        .accessibilityHint(saved ? "" : "Opens a recipe draft using this post")
    }

    private func plateButton(_ post: TablePost) -> some View {
        Button {
            togglePlate(post)
        } label: {
            HStack(spacing: 7) {
                PlateReactionGlyph(filled: post.platedByMeNow, size: 22)
                if typeSize.isAccessibilitySize {
                    Text(post.platedByMeNow ? "Liked" : "Like")
                        .plType(.footnote, .bold)
                        .plActionLabel()
                        .foregroundStyle(post.platedByMeNow ? Color.accentText : Color.inkSecondary)
                }
                // The numeral arrives with the first plate and not before.
                // A mounted zero beside every dinner somebody cooked is not
                // neutral in a room of eight people; it reads as a verdict
                // on a post nobody has got to yet. Instagram draws no like
                // row at zero, Slack no pill, Messages no chip: a reaction
                // display is evidence that something happened, never a
                // counter waiting to be filled.
                if post.totalPlates > 0 {
                    Text("\(post.totalPlates)")
                        .plType(.caption)
                        .foregroundStyle(post.platedByMeNow ? Color.accentText : Color.inkSecondary)
                        .contentTransition(.numericText())
                }
            }
            .animation(.plSnap, value: post.totalPlates)
            .plTapTarget()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(post.platedByMeNow ? "Remove your reaction" : "Like this post")
        .accessibilityValue(post.totalPlates.things("like"))
        .accessibilityAddTraits(post.platedByMeNow ? .isSelected : [])
    }

    private func commentLine(_ comment: TableComment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                (Text(comment.authorName)
                    .font(.custom(Font.SansWeight.bold.rawValue,
                                  size: TypeScale.footnote.size, relativeTo: .body))
                    .foregroundStyle(Color.ink)
                 + Text("  ")
                    .font(.custom(Font.SansWeight.regular.rawValue,
                                  size: TypeScale.footnote.size, relativeTo: .body))
                 + Text(comment.text)
                    .font(.custom(Font.SansWeight.regular.rawValue,
                                  size: TypeScale.footnote.size, relativeTo: .body))
                    .foregroundStyle(Color.inkSecondary))
                    .lineSpacing(2)
                if let url = URL.webLink(comment.linkURL) {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .bold))
                            Text(comment.linkLabel)
                                .plType(.micro)
                        }
                        .foregroundStyle(Color.accentText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(Color.chipFill, in: Radius.shape(Radius.chip))
                        .overlay(Radius.shape(Radius.chip).strokeBorder(Color.navHairline))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                }
            }
            Spacer(minLength: 0)
            if comment.deletedAt == nil {
                CommentReactionButton(comment: comment)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Actions

    private func togglePlate(_ post: TablePost) {
        var turningOn = false
        withAnimation(.plPop) {
            turningOn = TableReactions.togglePlate(
                post,
                context: context,
                authorName: reactionAuthorName
            )
        }
        if turningOn {
            post.hasChefsKiss(seats: seatCount) ? Haptic.kiss() : Haptic.plate()
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
        let dish = post.dishTitle.isEmpty ? "dish" : post.dishTitle
        Notifier.post(
            .saveReceived, actor: post.authorName,
            body: "You saved \(post.firstName)'s \(dish).",
            into: context,
            template: "You saved {actor}'s {object}.", actorID: post.authorID, objectTitle: dish
        )
        showToast("Saved to your cookbook")
    }

    private func showToast(_ message: String) {
        // The confirmation reaches the hand as well as the eye.
        Haptic.tap()
        AccessibilityNotification.Announcement(message).post()
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
        personDoor = .author(post.persistentModelID)
        personShown = PersonRef.author(
            post.authorName, colorHex: post.authorColorHex, authorID: post.authorID, in: members
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

    /// The byline-and-caption run, built once so the visible copy and the
    /// hidden measuring copy can never drift apart.
    ///
    /// Concatenated Text takes a Font, not a view modifier, so the scale is
    /// spelled out rather than applied. These are TypeScale.reading's numbers;
    /// keep them in step with it.
    private func captionText(_ post: TablePost) -> some View {
        let regular = Font.custom(Font.SansWeight.regular.rawValue, size: 14, relativeTo: .body)
        let strong = Font.custom(Font.SansWeight.semibold.rawValue, size: 14, relativeTo: .body)
        let cleanTitle = post.dishTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsStop = cleanTitle.last.map { !".!?…".contains($0) } ?? false
        let title = cleanTitle.isEmpty ? "" : cleanTitle + (needsStop && !post.caption.isEmpty ? ". " : " ")
        return (Text(post.firstName + " ").font(strong)
            + Text(title).font(regular)
            + Text(post.caption).font(regular))
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
        guard !contentSafety.isBlocked(authorID: post.authorID, authorName: post.authorName) else {
            showToast("This person's posts are hidden")
            return
        }
        Haptic.tap()
        threadStartsWriting = writing
        threadTargetComment = nil
        threadPost = post
    }

    /// The second leg of a tapped notice. Nothing to do is the common case.
    private func openRequestedPost() {
        guard let id = LinkRelay.takePost() else { return }
        let comment = LinkRelay.takeComment()
        if let post = TableNews.find(id, in: context) {
            open(post, comment: comment)
            return
        }
        // Not here yet: a banner raised on the iPad about a dish this
        // phone has not pulled, or a row that outlived its post. Ask the
        // table once before deciding which. The Table is already selected,
        // which is the honest place to land if it is gone.
        Task {
            await TablePull.pull(reason: "open")
            if let post = TableNews.find(id, in: context) {
                open(post, comment: comment)
            } else {
                showToast("This post is no longer available at your Table.")
            }
        }
    }

    private func open(_ post: TablePost, comment: String? = nil) {
        // Notification and universal-link requests can outlive the visible
        // feed. They must honor the same local block as a card tap.
        guard !contentSafety.isBlocked(authorID: post.authorID, authorName: post.authorName) else {
            showToast("This person's posts are hidden")
            return
        }
        pushed = nil
        personShown = nil
        threadStartsWriting = false
        threadTargetComment = comment
        threadPost = post
    }

    private func postWhen(_ date: Date) -> String {
        // The ladder itself lives in `Stamp` now, because the recipe page
        // needs the same rule and DESIGN.md states it as law. What stays here
        // is the one thing that is a fact about a POST rather than about a
        // date: dinner posted after five is "Tonight", not "Today". The clock
        // time rides along only while a weekday still means one thing.
        if Calendar.current.isDateInToday(date) {
            let hour = Calendar.current.component(.hour, from: date)
            return "\(hour >= 17 ? "Tonight" : "Today") · \(Self.timeFormat.string(from: date))"
        }
        let day = Stamp.day(date)
        guard Stamp.isRecent(date) else { return day }
        return "\(day) · \(Self.timeFormat.string(from: date))"
    }
}

/// A familiar heart is shared by feed and thread reactions. The persisted
/// reaction identity remains unchanged so existing likes retain their owners.
struct PlateReactionGlyph: View {
    var filled: Bool
    var size: CGFloat = 26
    var tone: Color = .inkSecondary

    var body: some View {
        Image(systemName: filled ? "heart.fill" : "heart")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(filled ? Color.accentText : tone)
            .accessibilityHidden(true)
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
                turningOn = TableReactions.togglePlate(
                    post,
                    context: context,
                    authorName: members.me?.name
                )
                bounce = true
            }
            if turningOn {
                // Same seating rule as the feed — this button lives outside
                // TableFeedView, so it cannot see seatCount.
                let seats = TableKiss.seating(members: members, dishAuthors: [post.authorName])
                post.hasChefsKiss(seats: seats) ? Haptic.kiss() : Haptic.plate()
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
            PlateReactionGlyph(filled: post.platedByMeNow, size: 22)
                .plTapTarget()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(post.platedByMeNow ? "Remove your reaction" : "Like this post")
        .accessibilityValue(post.totalPlates.things("like"))
        .accessibilityAddTraits(post.platedByMeNow ? .isSelected : [])
    }
}
