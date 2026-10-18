import SwiftUI
import SwiftData
import PhotosUI

/// One post, opened into a page — photo big, every comment threaded below,
/// the composer pinned. Replies point at people, @ mentions ring the
/// household, photos land in the talk, and every name is a door to a
/// profile. The back chevron is always top-left; no sheet to guess at.
struct PostThreadView: View {
    let post: TablePost
    /// Land with the keyboard up when the door said "Add a comment".
    ///
    /// That label is a verb naming an outcome, and tapping it used to push a
    /// page and ask you to tap again. Instagram's equivalent line opens with
    /// the field ready. Entering through the photo or the card body does not
    /// set this, because there the intent was "read the thread".
    var startWriting = false
    var targetComment: String?
    @State private var focusedComment: String?
    @State private var lastFocusedComment: String?
    /// Provided by the feed (which owns its toast); when nil — a thread
    /// opened from a profile page — the thread runs the save flow itself.
    var onSave: ((TablePost) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.activeAppTab) private var activeAppTab
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL
    @AppStorage("userFirstName") private var userFirstName = ""
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var recipes: [Recipe]

    @State private var draft = ""
    @State private var sendProblem: String?
    @State private var retryingComments: Set<String> = []
    /// Which face this profile was opened from. A thread offers four
    /// doors to the same person — a tagged chip, the author's row, a
    /// comment's avatar and that comment's name — and two sources may not
    /// share one id in one namespace, so the tap records the one it used.
    @State private var personDoor: ZoomID = .host
    @Namespace private var zoom
    @State private var link = ""
    @State private var linkFieldShown = false
    @State private var replyTo: String?
    @State private var replyToID: String?
    @State private var collapsedReplies = Set<String>()
    @State private var mentionBarShown = false
    @State private var photoItem: PhotosPickerItem?
    @State private var commentPhoto: Data?
    @State private var bounce = false
    @State private var personShown: PersonRef?
    @State private var localSave: TablePost?
    @State private var saveToast: String?
    @State private var saveToastToken = 0
    @State private var presenceHomeTab: AppTab?
    @State private var contentSafety = ContentSafety.shared
    @State private var safetyDialog: SafetyDialog?
    @FocusState private var composerFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One arrival for every rising element on this page — the comment, the
    /// composer's two, and the toast. Guarding only the first left three
    /// siblings sliding under Reduce Motion.
    ///
    /// It is a property so a new riser cannot be added unguarded. That only
    /// works if every site uses it: this shipped with three of four, the
    /// fourth still carrying a verbatim copy of the expression below —
    /// behaviourally identical, and exactly the divergence the property
    /// exists to make impossible. A shared thing used by most call sites is
    /// the same bug wearing the shape of its own cure.
    private var arrival: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private enum SafetyDialog {
        case report(ContentSafety.ReportTarget)
        case block(ContentSafety.Author, dismissThread: Bool)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Color.hairlineSoft)

            ScrollViewReader { scroll in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    postHeading
                    if let data = post.photoData, let image = UIImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            PhotoWell(image: image, height: 180)
                                .plCardShadow()
                            if post.hasChefsKiss(seats: TableKiss.seating(members: members, dishAuthors: [post.authorName])) {
                                chefsKissPill.offset(x: 6, y: -10)
                            }
                        }
                    }

                    HStack(spacing: 14) {
                        PlateReactionButton(post: post, bounce: $bounce)
                        // The same rule as the feed card: the line arrives
                        // with the first plate. "0 plates" under somebody's
                        // dinner is a sentence no social product writes.
                        if post.totalPlates > 0 {
                            Text(post.totalPlates.things("like"))
                                .plType(.footnote, .semibold)
                                .foregroundStyle(Color.inkSecondary)
                        }
                        Spacer()
                    }

                    if !post.caption.isEmpty || post.dishTitle.isEmpty {
                        Text(post.caption)
                            .plType(.body, .regular)
                            .foregroundStyle(Color.ink)
                            .lineSpacing(3)
                    }

                    if !post.taggedNames.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(post.taggedNames, id: \.self) { name in
                                    Button {
                                        openProfile(name, door: .person(name))
                                    } label: {
                                        Text("@\(name)")
                                            .matchedTransitionSource(id: ZoomID.person(name), in: zoom)
                                            .plType(.micro)
                                            .plActionLabel()
                                            .foregroundStyle(Color.ink)
                                            .padding(.horizontal, 10)
                                            .frame(minHeight: 30)
                                            .overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline))
                                            .frame(minHeight: 44)
                                            .contentShape(Radius.shape(Radius.chip))
                                    }
                                    .buttonStyle(.pressable)
                                }
                                Spacer()
                            }
                        }
                    }

                    if post.hasPoll {
                        pollCard
                    }

                    // The count only once there is one. "COMMENTS · 0"
                    // sitting directly above "No comments yet" says the same
                    // nothing twice.
                    MicroLabel(visibleComments.filter { $0.deletedAt == nil }.isEmpty
                               ? "Comments"
                               : "Comments · \(visibleComments.filter { $0.deletedAt == nil }.count)")
                        .padding(.top, 8)

                    if visibleComments.isEmpty {
                        Text(post.kind == "ask"
                             ? "No replies yet. Be the first to answer."
                             : "No comments yet. Start the conversation below.")
                            .plType(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                    }

                    ForEach(threadRows, id: \.comment.persistentModelID) { row in
                        VStack(alignment: .leading, spacing: 0) {
                            threadComment(row.comment)
                            let children = descendantCount(row.comment.shareRecordName)
                            if children > 0 {
                                Button(collapsedReplies.contains(row.comment.shareRecordName)
                                       ? (children == 1 ? "Show 1 reply" : "Show \(children) replies") : "Hide replies") {
                                    Haptic.select()
                                    withAnimation(.plSnap) {
                                        if collapsedReplies.contains(row.comment.shareRecordName) { collapsedReplies.remove(row.comment.shareRecordName) }
                                        else { collapsedReplies.insert(row.comment.shareRecordName) }
                                    }
                                }.plType(.caption, .bold).foregroundStyle(Color.inkSecondary).plTapTarget()
                            }
                        }
                        .padding(.leading, row.depth > 0 ? 16 : 0)
                        .overlay(alignment: .leading) {
                            if row.depth > 0 { Rectangle().fill(Color.hairline).frame(width: 1) }
                        }
                        .background(focusedComment == row.comment.shareRecordName ? Color.oliveTint : Color.clear,
                                    in: Radius.shape(Radius.chip))
                        .id(row.comment.shareRecordName)
                        .transition(arrival)
                    }
                }
                .animation(.plSnap, value: visibleComments.count)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .accessibilityIdentifier("table-post-thread")
            .task(id: (targetComment ?? "") + visibleComments.map(\.shareRecordName).joined()) {
                guard let targetComment, targetComment != lastFocusedComment,
                      visibleComments.contains(where: { $0.shareRecordName == targetComment }) else { return }
                collapsedReplies.removeAll()
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                withAnimation(.plSnap) { scroll.scrollTo(targetComment, anchor: .center) }
                lastFocusedComment = targetComment
                focusedComment = targetComment
                defer { focusedComment = nil }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                withAnimation(.plSnap) { focusedComment = nil }
            }
            }

            if let sendProblem { Text(sendProblem).plType(.caption).foregroundStyle(Color.dangerText).padding(.horizontal, 24) }
            composer
        }
        .background(Color.canvas)
        .onAppear {
            let key = "table.replyDraft." + (post.shareRecordName.isEmpty ? String(describing: post.persistentModelID) : post.shareRecordName)
            if let saved = UserDefaults.standard.dictionary(forKey: key) {
                draft = saved["text"] as? String ?? ""
                link = saved["link"] as? String ?? ""
                replyTo = saved["replyTo"] as? String
                replyToID = saved["parent"] as? String
                commentPhoto = saved["photo"] as? Data
            }
        }
        .onChange(of: draft) { saveReplyDraft() }
        .onChange(of: link) { saveReplyDraft() }
        .onChange(of: commentPhoto) { saveReplyDraft() }
        .onChange(of: replyToID) { saveReplyDraft() }
        .toolbar(.hidden, for: .navigationBar)
        // A beat after the push, not during it: focusing mid-transition
        // races the keyboard against the navigation animation and the page
        // arrives already scrolled.
        .task {
            guard startWriting else { return }
            try? await Task.sleep(for: .milliseconds(350))
            composerFocused = true
        }
        // A banner about this very thread would be the app tapping you on
        // the shoulder to point at what you are reading.
        .onAppear {
            if presenceHomeTab == nil { presenceHomeTab = activeAppTab }
            updatePostPresence()
            // Opening the dish is reading what was said about it: the bell
            // row, the icon's count and the banner still in the list.
            Task { await TableNews.markRead(post: post.shareRecordName, context: context) }
        }
        .onDisappear {
            if Presence.shared.openPost == post.shareRecordName { Presence.shared.openPost = nil }
        }
        .onChange(of: activeAppTab) { _, _ in updatePostPresence() }
        .onChange(of: personShown) { _, _ in updatePostPresence() }
        // This page docks its own composer at the bottom-trailing corner,
        // exactly where the perch lives.
        .hidesProngsbyPerch()
        .hidesFloatingChrome()
        .plSwipeBack()
        .navigationDestination(item: $personShown) { person in
            PersonProfileView(personName: person.name, colorHex: person.colorHex, memberID: person.memberID, authorID: person.authorID)
                .navigationTransition(.zoom(sourceID: personDoor, in: zoom))
        }
        .sheet(item: $localSave) { post in
            RecipeEditorView(prefill: (
                title: post.dishTitle.isEmpty ? "From \(post.firstName)'s table" : post.dishTitle,
                summary: post.caption,
                photo: post.photoData,
                originID: post.originKey
            )) { _ in
                if !postIsMine {
                    Awards.recordSaveReceived(by: post.authorName)
                    let dish = post.dishTitle.isEmpty ? "dish" : post.dishTitle
                    Notifier.post(
                        .saveReceived, actor: post.authorName,
                        body: "You saved \(post.firstName)'s \(dish).",
                        into: context,
                        template: "You saved {actor}'s {object}.",
                        actorID: post.authorID, objectTitle: dish
                    )
                }
                showSaveToast("Saved to your cookbook")
            }
        }
        .confirmationDialog(
            safetyDialogTitle,
            isPresented: Binding(
                get: { safetyDialog != nil },
                set: { if !$0 { safetyDialog = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let safetyDialog {
                switch safetyDialog {
                case .report(let target):
                    ForEach(ContentSafety.ReportReason.allCases) { reason in
                        Button(reason.rawValue) { report(target, because: reason) }
                    }
                    Button("Cancel", role: .cancel) {}
                case .block(let author, let dismissThread):
                    Button("Block \(author.label)", role: .destructive) {
                        block(author, dismissThread: dismissThread)
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        } message: {
            Text(safetyDialogMessage)
        }
        .overlay(alignment: .bottom) {
            if let toast = saveToast {
                Text(toast)
                    .plType(.footnote, .bold)
                    .foregroundStyle(Color.canvas)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .background(Color.ink, in: Radius.shape(Radius.chip))
                    .padding(.bottom, 150)
                    .transition(arrival)
            }
        }
        .onChange(of: photoItem, initial: false) { _, item in
            guard let item else { return }
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self) {
                    commentPhoto = ProfilePhoto.downscale(raw)
                }
            }
        }
    }

    // MARK: Pieces

    @State private var attachmentsExpanded = false

    private var topBar: some View {
        HStack(spacing: 10) {
            IconDiscButton(systemName: "arrow.left", label: "Back") {
                dismiss()
            }
            Text("Post").plType(.heading).foregroundStyle(Color.ink)
            Spacer()
            if canSaveToCookbook || canReport(postAuthor, knownToBeSelf: postIsMine) || canBlock(postAuthor) {
                Menu {
                    if canSaveToCookbook {
                        Button(action: save) {
                            Label("Save to cookbook", systemImage: "book")
                        }
                    }
                    Section {
                        safetyActions(
                            target: .post(post),
                            author: postAuthor,
                            contentLabel: "post",
                            dismissThreadOnBlock: true,
                            reportAllowed: canReport(postAuthor, knownToBeSelf: postIsMine),
                            blockAllowed: canBlock(postAuthor)
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                        .plTapTarget()
                }
                .accessibilityLabel("Post options")
                .accessibilityIdentifier("table-thread-options")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var canSaveToCookbook: Bool {
        post.kind == "dish" && !recipes.contains { $0.originID == post.originKey }
    }

    private var postHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                openProfile(post.authorName, colorHex: post.authorColorHex, authorID: post.authorID, door: .author(post.persistentModelID))
            } label: {
                HStack(spacing: 10) {
                    AvatarCircle(initials: post.initials, tone: PersonTone.from(hex: post.authorColorHex), size: 38,
                                 photo: members.photo(forAuthor: post.authorName, authorID: post.authorID))
                        .matchedTransitionSource(id: ZoomID.author(post.persistentModelID), in: zoom)
                    Text(post.authorName).plType(.footnote, .semibold).foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }.contentShape(Rectangle())
            }.buttonStyle(.pressable)
            Text(post.dishTitle.isEmpty ? (post.kind == "ask" ? "Question" : "Post") : post.dishTitle)
                .plType(.heading).foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The poll — vote bars that fill live, one vote each, change your mind
    /// freely.
    private var pollCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel("Poll")
            ForEach(Array(post.pollOptions.enumerated()), id: \.offset) { index, option in
                pollRow(index: index, option: option)
            }
            Text(post.totalPollVotes == 1 ? "1 vote" : "\(post.totalPollVotes) votes")
                .plType(.micro, .semibold)
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))
    }

    private func pollRow(index: Int, option: String) -> some View {
        let votes = post.votes(for: index)
        let total = max(post.totalPollVotes, 1)
        let fraction = Double(votes) / Double(total)
        let mine = post.myVote == index
        return Button {
            Haptic.plate()
            withAnimation(.plSnap) {
                TableReactions.vote(
                    post,
                    option: index,
                    context: context,
                    authorName: currentAuthorName
                )
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mine ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(mine ? Color.basil : Color.inkFaint)
                    // The tick is drawn into the ring you already voted
                    // against, rather than one symbol cutting to another.
                    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
                Text(option)
                    .plType(.body, mine ? TypeWeight.bold : .semibold)
                    .foregroundStyle(Color.ink)
                Spacer()
                Text("\(votes)")
                    .plType(.footnote, .bold)
                    .foregroundStyle(mine ? Color.completion : Color.inkSecondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(mine ? Color.basilTint : Color.hairlineSoft)
                        .frame(width: max(proxy.size.width * fraction, votes > 0 ? 20 : 0))
                        .animation(.plSnap, value: fraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).strokeBorder(mine ? Color.basil.opacity(0.4) : Color.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(option)
        .accessibilityValue("\(votes.things("vote"))\(mine ? ", your choice" : "")")
        .accessibilityHint(mine ? "Double tap to remove your vote" : "Double tap to vote")
        .accessibilityAddTraits(mine ? .isSelected : [])
    }

    private func commentKey(_ comment: TableComment) -> String { comment.shareRecordName.isEmpty ? String(describing: comment.persistentModelID) : comment.shareRecordName }

    private var postAuthor: ContentSafety.Author {
        ContentSafety.Author(identity: post.authorID, displayName: post.authorName)
    }

    private var postIsMine: Bool {
        TableMutationAuthorization.owns(
            post: post,
            identityIDs: currentIdentityIDs,
            displayNames: currentDisplayNames
        )
    }

    private func author(for comment: TableComment) -> ContentSafety.Author {
        ContentSafety.Author(identity: comment.authorID, displayName: comment.authorName)
    }

    private func canBlock(_ author: ContentSafety.Author) -> Bool {
        contentSafety.canBlock(
            author,
            currentIdentityIDs: currentIdentityIDs,
            currentDisplayNames: currentDisplayNames
        )
    }

    private func canReport(_ author: ContentSafety.Author, knownToBeSelf: Bool) -> Bool {
        contentSafety.canReport(
            author,
            currentIdentityIDs: currentIdentityIDs,
            knownToBeSelf: knownToBeSelf
        )
    }

    /// Old comments have no identity. Treat an exact current name as known
    /// self only on a genuinely local legacy post; a shared row with the
    /// same first name remains reportable because ownership is ambiguous.
    private func isKnownSelfAuthoredLegacyComment(_ comment: TableComment) -> Bool {
        guard comment.authorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              post.authorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !post.isRemote,
              post.shareZoneOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        let target = normalizedSafetyName(comment.authorName)
        guard !target.isEmpty else { return false }
        return currentDisplayNames.contains { normalizedSafetyName($0) == target }
    }

    private func normalizedSafetyName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    @ViewBuilder
    private func safetyActions(
        target: ContentSafety.ReportTarget,
        author: ContentSafety.Author,
        contentLabel: String,
        dismissThreadOnBlock: Bool,
        reportAllowed: Bool,
        blockAllowed: Bool
    ) -> some View {
        if reportAllowed {
            Button {
                safetyDialog = .report(target)
            } label: {
                Label("Report \(contentLabel)", systemImage: "exclamationmark.bubble")
            }
        }
        if blockAllowed {
            Button(role: .destructive) {
                safetyDialog = .block(author, dismissThread: dismissThreadOnBlock)
            } label: {
                Label("Block \(author.firstName)", systemImage: "person.slash")
            }
        }
    }

    private var safetyDialogTitle: String {
        switch safetyDialog {
        case .report(let target):
            return "Why are you reporting this \(target.kind.rawValue)?"
        case .block(let author, _):
            return "Block \(author.label)?"
        case nil:
            return ""
        }
    }

    private var safetyDialogMessage: String {
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
            showSaveToast("Couldn't prepare the report email")
            return
        }
        Haptic.tap()
        openURL(url)
    }

    private func block(_ author: ContentSafety.Author, dismissThread: Bool) {
        safetyDialog = nil
        guard contentSafety.block(
            author,
            currentIdentityIDs: currentIdentityIDs,
            currentDisplayNames: currentDisplayNames
        ) else { return }
        WidgetBridge.publish(from: context)
        AppBadge.sync(context)

        let message = "\(author.firstName)'s posts and comments are hidden"
        let nowHidesPost = contentSafety.isBlocked(
            authorID: post.authorID,
            authorName: post.authorName
        )
        if dismissThread || nowHidesPost {
            Haptic.warn()
            AccessibilityNotification.Announcement(message).post()
            dismiss()
        } else {
            showSaveToast(message)
        }
    }

    /// Linearized tree with bounded indentation. Missing parents and cycles
    /// remain visible; stale sync data can never hide someone's comment.
    private var threadRows: [(comment: TableComment, depth: Int)] {
        let comments = visibleComments
        let ids = Set(comments.map(commentKey))
        var visited = Set<String>()
        var rows: [(comment: TableComment, depth: Int)] = []
        func append(_ comment: TableComment, depth: Int) {
            guard visited.insert(commentKey(comment)).inserted else { return }
            rows.append((comment, depth))
            if collapsedReplies.contains(commentKey(comment)) {
                func mark(_ id: String) {
                    for child in comments where child.parentCommentID == id {
                        if visited.insert(child.shareRecordName).inserted { mark(child.shareRecordName) }
                    }
                }
                mark(commentKey(comment))
            } else {
                for child in comments where child.parentCommentID == comment.shareRecordName { append(child, depth: depth + 1) }
            }
        }
        for comment in comments where comment.parentCommentID == nil || !ids.contains(comment.parentCommentID ?? "") { append(comment, depth: 0) }
        for comment in comments where !visited.contains(commentKey(comment)) { append(comment, depth: 0) }
        return rows
    }
    private func descendantCount(_ id: String) -> Int {
        var visited: Set<String> = [id]
        func visit(_ parent: String) {
            for child in visibleComments where child.parentCommentID == parent {
                if visited.insert(child.shareRecordName).inserted { visit(child.shareRecordName) }
            }
        }
        visit(id)
        return visited.count - 1
    }

    private func threadComment(_ comment: TableComment) -> some View {
        let removable = canRemove(comment)
        let commentAuthor = author(for: comment)
        let reportAllowed = canReport(
            commentAuthor,
            knownToBeSelf: isKnownSelfAuthoredLegacyComment(comment)
        ) && comment.deletedAt == nil
        let blockAllowed = canBlock(commentAuthor) && comment.deletedAt == nil
        return HStack(alignment: .top, spacing: 10) {
            Button {
                openProfile(comment.authorName, authorID: comment.authorID, door: .author(comment.persistentModelID))
            } label: {
                AvatarCircle(initials: initials(for: comment.authorName), tone: tone(for: comment.authorName), size: 30,
                             photo: members.photo(forAuthor: comment.authorName, authorID: comment.authorID))
                    .matchedTransitionSource(id: ZoomID.author(comment.persistentModelID), in: zoom)
                    .plTapTarget()
            }
            .buttonStyle(.pressable)
            // The adjacent name is the one VoiceOver door. Keeping the face
            // visually tappable without announcing the same profile twice
            // makes a long thread much faster to traverse.
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                let headingLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 6))
                headingLayout {
                    Button {
                        openProfile(comment.authorName, authorID: comment.authorID, door: .author(comment.persistentModelID))
                    } label: {
                        Text(comment.authorName)
                            .plType(.footnote, .bold)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(Color.ink)
                    }
                    .buttonStyle(.pressable)
                    .plTapTarget()
                    Text(relativeWhen(comment.createdAt))
                        .plType(.micro, .medium)
                        .foregroundStyle(Color.inkSecondary)
                }
                if !comment.replyToName.isEmpty && !post.sortedComments.contains(where: { $0.shareRecordName == comment.parentCommentID }) {
                    Label("Replying to \(comment.replyToName)", systemImage: "arrowshape.turn.up.left")
                        .plType(.micro)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if comment.deletedAt != nil {
                    Text("Comment deleted").plType(.body).foregroundStyle(Color.inkSecondary)
                } else { mentionedText(comment).lineSpacing(2) }
                if let pending = TableOutbox.shared.pending.first(where: {
                    if case .note(_, _, let id) = $0.work { return id == comment.shareRecordName }
                    return false
                }) {
                    HStack(spacing: 8) {
                        Text(pending.tries == 0 ? "Sending…" : "Saved on this phone · waiting to sync")
                            .plType(.caption).foregroundStyle(Color.inkSecondary)
                        if pending.tries > 0 {
                            Button("Retry") { retryComment(comment, entry: pending) }
                                .plType(.caption, .semibold).plTapTarget()
                                .disabled(retryingComments.contains(comment.shareRecordName))
                        }
                    }
                }
                if let data = comment.photoData {
                    RecipeArtwork(data: data, title: "Comment photo", ratio: 4.0 / 3.0, radius: Radius.chip)
                        .frame(maxWidth: 200)
                        .accessibilityHidden(false)
                        .accessibilityLabel("Attached photo")
                        .padding(.top, 2)
                }
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
                if comment.deletedAt == nil {
                    if typeSize.isAccessibilitySize { CommentReactionButton(comment: comment) }
                    HStack(spacing: 16) {
                        Button {
                            Haptic.tap()
                            withAnimation(.plSnap) {
                                replyTo = comment.authorName
                                replyToID = comment.shareRecordName
                                composerFocused = true
                            }
                        } label: {
                            Text("Reply")
                                .plType(.micro)
                                .plActionLabel()
                                .foregroundStyle(Color.inkSecondary)
                                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        Spacer(minLength: 0)
                        if removable || reportAllowed || blockAllowed {
                            Menu {
                                if removable {
                                    Button(role: .destructive) { remove(comment) } label: {
                                        Label("Delete comment", systemImage: "trash")
                                    }
                                }
                                if reportAllowed || blockAllowed {
                                    safetyActions(
                                        target: .comment(comment, on: post),
                                        author: commentAuthor,
                                        contentLabel: "comment",
                                        dismissThreadOnBlock: false,
                                        reportAllowed: reportAllowed,
                                        blockAllowed: blockAllowed
                                    )
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.inkSecondary)
                                    .plTapTarget()
                            }
                            .accessibilityLabel("More options for \(commentAuthor.label)'s comment")
                        }
                    }
                }
            }
            if comment.deletedAt == nil && !typeSize.isAccessibilitySize {
                CommentReactionButton(comment: comment).padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        // Take back what you said.
        //
        // There was no delete and no edit for a comment anywhere: not a
        // context menu, not a swipe, not an overflow. The only path that
        // removed one was deleting the whole post, which the cascade rule on
        // TablePost.comments takes everybody else's words with. Instagram,
        // Messages, WhatsApp and Slack all let an author remove their own
        // message, and Instagram additionally lets the post's owner clear a
        // comment on their own post. Both, here: your words are yours, and
        // your post is your table.
        //
        // SwiftUI's context menu is bridged to VoiceOver on its own, and
        // SwipeRow vends its actions through `.accessibilityActions`, so the
        // gesture has a non-gesture equivalent either way.
        .modifier(CommentActions(
            comment: comment,
            canRemove: removable,
            canReport: reportAllowed,
            canBlock: blockAllowed,
            remove: { remove(comment) },
            report: {
                safetyDialog = .report(.comment(comment, on: post))
            },
            block: {
                safetyDialog = .block(commentAuthor, dismissThread: false)
            }
        ))
    }

    private var visibleComments: [TableComment] {
        post.sortedComments.filter {
            !contentSafety.isBlocked(authorID: $0.authorID, authorName: $0.authorName)
        }
    }

    /// Your own comment, or any comment on your own post.
    private func canRemove(_ comment: TableComment) -> Bool {
        guard comment.deletedAt == nil else { return false }
        return TableMutationAuthorization.canDelete(
            comment: comment,
            on: post,
            identityIDs: currentIdentityIDs,
            displayNames: currentDisplayNames
        )
    }

    private func remove(_ comment: TableComment) {
        // Context menus are snapshots. Re-check at the destructive edge in
        // case the account or the row changed while the menu was open.
        guard canRemove(comment) else { return }
        Haptic.warn()
        withAnimation(.plSnap) {
            comment.deletedAt = .now
            comment.text = ""
            comment.linkURL = ""
            comment.photoData = nil
            comment.mentions = []
        }
        TableReactions.forgetComments([comment.shareRecordName])
        Persist.save(context, "delete comment")
        let queued = TableOutbox.shared.enqueue(
            .note(post: post.shareRecordName, zoneOwner: post.shareZoneOwner, id: comment.shareRecordName),
            author: TableIdentity.cached
        )
        Task {
            let sent = await TableShare.pushNote(
                comment,
                post: post.shareRecordName,
                zoneOwner: post.shareZoneOwner
            )
            TableOutbox.shared.finish(queued, succeeded: sent)
        }
    }

    private var currentAuthorName: String {
        let typed = userFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? (members.me?.name ?? "") : typed
    }

    private var currentIdentityIDs: [String] {
        [TableIdentity.cached, members.me?.participantID, members.me?.userRecordName]
            .compactMap { $0 }
    }

    private var currentDisplayNames: [String] {
        [members.me?.name, userFirstName].compactMap { $0 }
    }

    /// The comment body, with the names in it drawn as names.
    ///
    /// This split the body on spaces and tested each word, so "@Sam Meadows"
    /// was resolved correctly on the way in — `send()` matches against the
    /// full member name — and then drawn as ordinary text on the way out,
    /// because `"Sam".hasPrefix("Sam Meadows")` is false. Every household
    /// where somebody is stored with a surname had mentions that worked
    /// everywhere except on screen.
    ///
    /// Ranged over the string rather than tokenised: a name is a range, not
    /// a word. Longest first, so "@Sam Meadows" is matched before "@Sam"
    /// eats its first half.
    private func mentionedText(_ comment: TableComment) -> Text {
        let body = comment.text
        let plain = Font.sans(TypeScale.body.size)
        let bold = Font.sans(TypeScale.body.size, .bold)
        guard !comment.mentions.isEmpty else {
            return Text(body).font(plain).foregroundStyle(Color.ink)
        }

        // Every "@name" occurrence, longest name first.
        var spans: [Range<String.Index>] = []
        for name in comment.mentions.sorted(by: { $0.count > $1.count }) {
            var from = body.startIndex
            while let found = body.range(of: "@\(name)", range: from..<body.endIndex) {
                if !spans.contains(where: { $0.overlaps(found) }) { spans.append(found) }
                from = found.upperBound
            }
        }
        spans.sort { $0.lowerBound < $1.lowerBound }

        var result = Text("")
        var cursor = body.startIndex
        for span in spans {
            if cursor < span.lowerBound {
                result = result + Text(String(body[cursor..<span.lowerBound]))
                    .font(plain).foregroundStyle(Color.ink)
            }
            result = result + Text(String(body[span]))
                .font(bold).foregroundStyle(Color.ink)
            cursor = span.upperBound
        }
        if cursor < body.endIndex {
            result = result + Text(String(body[cursor...])).font(plain).foregroundStyle(Color.ink)
        }
        return result
    }

    private var composer: some View {
        VStack(spacing: 8) {
            Divider().overlay(Color.hairlineSoft)

            if let replyTo {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.inkFaint)
                    Text("Replying to \(replyTo)")
                        .plType(.caption, .bold)
                        .foregroundStyle(Color.inkSecondary)
                    Spacer()
                    Button {
                        withAnimation(.plSnap) { self.replyTo = nil; self.replyToID = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Cancel reply")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
                .padding(.horizontal, 24)
                .transition(arrival)
            }

            if mentionBarShown {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(members, id: \.persistentModelID) { member in
                            Button {
                                Haptic.tap()
                                draft += (draft.isEmpty || draft.hasSuffix(" ") ? "" : " ") + "@\(member.name) "
                                mentionBarShown = false
                            } label: {
                                HStack(spacing: 5) {
                                    AvatarCircle(member: member, size: 22)
                                    Text(member.name)
                                        .plName()
                                        .plType(.micro)
                                        .plActionLabel()
                                        .foregroundStyle(Color.ink)
                                }
                                .padding(.horizontal, 10)
                                .frame(minHeight: 34)
                                .overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline))
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .transition(arrival)
            }

            if linkFieldShown {
                TextField("Paste a link", text: $link)
                    // .body, like the other nineteen text inputs in the app.
                    // This was the only one set a step down, so typing into
                    // it felt like a different app.
                    .plType(.body, .medium)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .padding(.horizontal, 24)
                    .plTappableField()
            }

            if let commentPhoto, let image = UIImage(data: commentPhoto) {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.plSnap) { self.commentPhoto = nil }
                            } label: {
                                Circle()
                                    .fill(Color.scrim)
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        Image(systemName: "xmark")
                                            .accessibilityLabel("Remove photo")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(Color.onScrim)
                                    }
                                    .frame(width: 44, height: 44, alignment: .topTrailing)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)
                        }
                    Spacer()
                }
                .padding(.horizontal, 24)
            }

            if attachmentsExpanded {
                HStack(spacing: 6) {
                Button {
                    Haptic.tap()
                    withAnimation(.plSnap) { mentionBarShown.toggle() }
                } label: {
                    Image(systemName: "at")
                        .accessibilityLabel("Mention someone")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(mentionBarShown ? Color.ink : Color.inkSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo")
                        .accessibilityLabel("Add a photo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(commentPhoto == nil ? Color.inkSecondary : Color.ink)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)

                Button {
                    Haptic.tap()
                    withAnimation(.plSnap) { linkFieldShown.toggle() }
                } label: {
                    Image(systemName: "link")
                        .accessibilityLabel("Add a link")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(linkFieldShown ? Color.ink : Color.inkSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)

                    Spacer()
                }.padding(.horizontal, 20)
            }
            HStack(alignment: .bottom, spacing: 6) {
                DesignIconButton(symbol: attachmentsExpanded ? "minus" : "plus", label: attachmentsExpanded ? "Hide attachments" : "Add attachment or mention") {
                    withAnimation(.plSnap) { attachmentsExpanded.toggle() }
                }
                TextField(typeSize.isAccessibilitySize ? "Write…" : placeholder, text: $draft, axis: .vertical)
                    .accessibilityLabel(placeholder)
                    .plType(.body, .medium)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .plTapToFocus { composerFocused = true }
                    // The padding is part of the pill but not of the text
                    // field — without this, taps on it go nowhere.
                    .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .onTapGesture { composerFocused = true }
                    .onChange(of: draft) { _, text in
                        if text.hasSuffix("@") {
                            withAnimation(.plSnap) { mentionBarShown = true }
                        }
                    }

                Button {
                    send()
                } label: {
                    Circle()
                        .fill(canSend ? Color.primaryAction : Color.fill)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "arrow.up")
                                .accessibilityLabel("Send")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(canSend ? Color.onPrimary : Color.inkSecondary)
                        }
                        .plTapTarget()
                }
                .buttonStyle(.pressable)
                .disabled(!canSend)
            }
            .padding(.horizontal, 20)
            // Threads are focused destinations, so the root tray retires and
            // the composer only owes the home indicator a small breath.
            .padding(.bottom, 10)
            .animation(.plSnap, value: composerFocused)
        }
    }

    private var placeholder: String {
        if replyTo != nil { return "Your reply…" }
        return post.kind == "ask" ? "Add a reply…" : "Add a comment…"
    }

    private var canSend: Bool {
        // The link field is there so a comment can BE a link. Requiring
        // text as well made it decoration.
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || commentPhoto != nil
            || !link.trimmingCharacters(in: .whitespaces).isEmpty
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
    }

    // MARK: Actions

    /// Feed threads delegate to the feed's flow; profile-opened threads run
    /// their own — same editor, same credit, never a dead button.
    private func save() {
        if let onSave {
            onSave(post)
            return
        }
        Haptic.tap()
        if recipes.contains(where: { $0.originID == post.originKey }) {
            showSaveToast("Already in your cookbook")
            return
        }
        localSave = post
    }

    private func showSaveToast(_ message: String) {
        // The confirmation reaches the hand as well as the eye.
        Haptic.tap()
        AccessibilityNotification.Announcement(message).post()
        saveToastToken += 1
        let token = saveToastToken
        withAnimation(.plSnap) { saveToast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if saveToastToken == token {
                withAnimation(.plSnap) { saveToast = nil }
            }
        }
    }

    private func saveReplyDraft() {
        let key = "table.replyDraft." + (post.shareRecordName.isEmpty ? String(describing: post.persistentModelID) : post.shareRecordName)
        if draft.isEmpty && link.isEmpty && commentPhoto == nil {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            var value: [String: Any] = ["text": draft, "link": link]
            value["replyTo"] = replyTo; value["parent"] = replyToID; value["photo"] = commentPhoto
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    private func retryComment(_ comment: TableComment, entry: TableOutbox.Entry) {
        guard !retryingComments.contains(comment.shareRecordName) else { return }
        retryingComments.insert(comment.shareRecordName)
        Task {
            let sent = await TableShare.pushNote(comment, post: post.shareRecordName, zoneOwner: post.shareZoneOwner)
            TableOutbox.shared.finish(entry, succeeded: sent)
            retryingComments.remove(comment.shareRecordName)
        }
    }

    private func send() {
        let author = currentAuthorName.isEmpty ? "Me" : currentAuthorName
        let cleanDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = cleanLink.isEmpty ? "" : (cleanLink.hasPrefix("http") ? cleanLink : "https://\(cleanLink)")
        let mentioned = members.map(\.name).filter { draft.contains("@\($0)") }
        let comment = TableComment(
            authorName: author,
            // Not a camera emoji. `canSend` deliberately allows a comment
            // that is only a link, and this stamped every one of them with
            // a 📷 in the body — so a pasted recipe URL rendered as a
            // photograph that was not there. An empty body with a link or a
            // photo carrying the row is a valid comment and every renderer
            // already handles it.
            text: cleanDraft,
            linkURL: normalized,
            replyToName: replyTo ?? "",
            mentions: mentioned,
            photoData: commentPhoto,
            authorID: TableIdentity.cached
        )
        comment.parentCommentID = replyToID
        comment.post = post
        context.insert(comment)
        let activityBefore = Set(context.insertedModelsArray.compactMap { ($0 as? PlatedNotification)?.persistentModelID })
        if post.authorName != author && post.firstName != author {
            Notifier.post(
                .commentAdded, actor: author,
                body: replyTo == nil
                    ? "\(author) commented on \(post.firstName)'s \(post.dishTitle.isEmpty ? "post" : post.dishTitle)."
                    : "\(author) replied to \(replyTo ?? "") on \(post.firstName)'s post.",
                into: context
            )
        }
        // Save the comment (and its local activity row) before clearing the
        // composer, queueing it or touching the network. The queue is
        // written first and removed only after CloudKit confirms the exact
        // version that was sent, so a force-quit or a quick delete cannot
        // lose the latest intent.
        guard Persist.save(context, "post comment") else {
            let insertedActivity = context.insertedModelsArray.compactMap { $0 as? PlatedNotification }
                .filter { !activityBefore.contains($0.persistentModelID) }
            for note in insertedActivity { context.delete(note) }
            context.delete(comment)
            sendProblem = "Couldn't save your comment. Your writing is still here. Try sending again."
            return
        }
        sendProblem = nil
        let postRecord = post.shareRecordName
        let zoneOwner = post.shareZoneOwner
        let queued = TableOutbox.shared.enqueue(
            .note(post: postRecord, zoneOwner: zoneOwner, id: comment.shareRecordName),
            author: comment.authorID
        )
        Task {
            let sent = await TableShare.pushNote(comment, post: postRecord, zoneOwner: zoneOwner)
            TableOutbox.shared.finish(queued, succeeded: sent)
        }
        Haptic.plate()
        AccessibilityNotification.Announcement(replyTo == nil ? "Comment saved, sending to your Table" : "Reply saved, sending to your Table").post()
        draft = ""
        link = ""
        linkFieldShown = false
        commentPhoto = nil
        photoItem = nil
        withAnimation(.plSnap) { replyTo = nil; replyToID = nil }
    }

    private func openProfile(_ name: String, colorHex: String? = nil, authorID: String = "", door: ZoomID) {
        Haptic.tap()
        personDoor = door
        let hex = colorHex
            ?? members.first { $0.name == name || name.hasPrefix($0.name) }?.colorHex
            ?? "FF5A3C"
        personShown = PersonRef.author(name, colorHex: hex, authorID: authorID, in: members)
    }

    private func updatePostPresence() {
        let visible = activeAppTab == presenceHomeTab && personShown == nil
        if visible {
            Presence.shared.openPost = post.shareRecordName
        } else if Presence.shared.openPost == post.shareRecordName {
            Presence.shared.openPost = nil
        }
    }

    private func tone(for name: String) -> PersonTone {
        if let member = members.first(where: { $0.name == name || name.hasPrefix($0.name) }) {
            return member.tone
        }
        return .neutralPair
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
            .filter { $0.first?.isLetter == true }
            .prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private func relativeWhen(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

/// A swipe and a long press over one comment row, or neither.
///
/// A modifier rather than a branch in the row body: `SwipeRow` wraps its
/// content, so putting an `if` around it would swap SwiftUI's identity
/// between a removable and a non-removable comment and tear the row down
/// mid-scroll.
private struct CommentActions: ViewModifier {
    let comment: TableComment
    let canRemove: Bool
    let canReport: Bool
    let canBlock: Bool
    let remove: () -> Void
    let report: () -> Void
    let block: () -> Void

    @ViewBuilder
    private var menu: some View {
        if canRemove {
            Button(role: .destructive, action: remove) {
                Label("Delete comment", systemImage: "trash")
            }
        }
        if canReport {
            Button(action: report) {
                Label("Report comment", systemImage: "exclamationmark.bubble")
            }
        }
        if canBlock {
            Button(role: .destructive, action: block) {
                Label("Block \(comment.authorName.split(separator: " ").first.map(String.init) ?? "person")", systemImage: "person.slash")
            }
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if canRemove {
            SwipeRow(isOpen: .constant(false), actions: [.remove(remove)]) {
                content
            }
            .contextMenu {
                menu
            }
        } else if canReport || canBlock {
            content.contextMenu { menu }
        } else {
            content
        }
    }
}
