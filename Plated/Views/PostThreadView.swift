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
    /// Provided by the feed (which owns its toast); when nil — a thread
    /// opened from a profile page — the thread runs the save flow itself.
    var onSave: ((TablePost) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userFirstName") private var userFirstName = ""
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var recipes: [Recipe]

    @State private var draft = ""
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

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Color.hairlineSoft)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let data = post.photoData, let image = UIImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            PhotoWell(image: image, clamped: true)
                                .plCardShadow()
                            if post.hasChefsKiss(seats: members.count) {
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
                            Text(post.totalPlates == 1 ? "1 plate" : "\(post.totalPlates) plates")
                                .plType(.footnote, .semibold)
                                .foregroundStyle(Color.inkSecondary)
                        }
                        Spacer()
                    }

                    // The byline-and-caption run, on the same condition the
                    // feed card uses. Unguarded, a post with no caption drew
                    // the bold name and its two trailing spaces and nothing
                    // else: a name sitting alone under the plate, saying
                    // nothing, while the same name is already in the bar
                    // above it. The feed learned this and the thread did not.
                    if !post.caption.isEmpty || post.dishTitle.isEmpty {
                        // Spelled out because concatenated Text takes a Font,
                        // not a view modifier. TypeScale.body's numbers.
                        (Text(post.authorName).font(.jakarta(TypeScale.body.size, .bold))
                         + Text("  ").font(.jakarta(TypeScale.body.size))
                         + Text(post.caption).font(.jakarta(TypeScale.body.size)))
                            .foregroundStyle(Color.ink)
                            .lineSpacing(3)
                    }

                    if !post.taggedNames.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(post.taggedNames, id: \.self) { name in
                                Button {
                                    openProfile(name, door: .person(name))
                                } label: {
                                    // The whole target was the glyph box:
                                    // about 22 by 14 points for a short
                                    // name. It is a chip inside a 44pt
                                    // frame now, the same two-frame shape
                                    // the Save pill above it uses.
                                    Text("@\(name)")
                                        .matchedTransitionSource(id: ZoomID.person(name), in: zoom)
                                        .plType(.micro)
                                        .foregroundStyle(Color.ink)
                                        .padding(.horizontal, 10)
                                        .frame(minHeight: 30)
                                        .overlay(Capsule().strokeBorder(Color.hairline))
                                        .frame(minHeight: 44)
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.pressable)
                            }
                            Spacer()
                        }
                    }

                    if post.hasPoll {
                        pollCard
                    }

                    // The count only once there is one. "COMMENTS · 0"
                    // sitting directly above "No comments yet" says the same
                    // nothing twice.
                    MicroLabel(post.sortedComments.isEmpty
                               ? "Comments"
                               : "Comments · \(post.sortedComments.count)")
                        .padding(.top, 8)

                    if post.sortedComments.isEmpty {
                        Text(post.kind == "ask" ? "No suggestions yet" : "No comments yet")
                            .plType(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                    }

                    ForEach(threadRows, id: \.comment.persistentModelID) { row in
                        VStack(alignment: .leading, spacing: 0) {
                            threadComment(row.comment)
                            let children = descendantCount(row.comment.shareRecordName)
                            if children > 0 {
                                Button(collapsedReplies.contains(row.comment.shareRecordName) ? "Show \(children) replies" : "Hide replies") {
                                    Haptic.select()
                                    withAnimation(.plSnap) {
                                        if collapsedReplies.contains(row.comment.shareRecordName) { collapsedReplies.remove(row.comment.shareRecordName) }
                                        else { collapsedReplies.insert(row.comment.shareRecordName) }
                                    }
                                }.plType(.caption, .bold).foregroundStyle(Color.inkSecondary).plTapTarget()
                            }
                        }
                        .padding(.leading, CGFloat(min(row.depth, 2)) * 16)
                        .transition(arrival)
                    }
                }
                .animation(.plSnap, value: post.sortedComments.count)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }

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
        // This page docks its own composer at the bottom-trailing corner,
        // exactly where the perch lives.
        .hidesProngsbyPerch()
        .plSwipeBack()
        .navigationDestination(item: $personShown) { person in
            PersonProfileView(personName: person.name, colorHex: person.colorHex, memberID: person.memberID)
                .navigationTransition(.zoom(sourceID: personDoor, in: zoom))
        }
        .sheet(item: $localSave) { post in
            RecipeEditorView(prefill: (
                title: post.dishTitle.isEmpty ? "From \(post.firstName)'s table" : post.dishTitle,
                summary: post.caption,
                photo: post.photoData,
                originID: post.originKey
            )) { _ in
                Awards.recordSaveReceived(by: post.authorName)
                let me = members.first(where: \.isOwner)?.name ?? "Someone"
                Notifier.post(
                    .saveReceived, actor: me,
                    body: "You saved \(post.firstName)'s \(post.dishTitle.isEmpty ? "dish" : post.dishTitle). They get the credit.",
                    into: context
                )
                showSaveToast("Saved. \(post.firstName) gets the credit")
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = saveToast {
                Text(toast)
                    .plType(.footnote, .bold)
                    .foregroundStyle(Color.canvas)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .background(Color.ink, in: Capsule())
                    .padding(.bottom, 150)
                    .transition(arrival)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self) {
                    commentPhoto = PersonProfileView.downscale(raw)
                }
            }
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack(spacing: 10) {
            IconDiscButton(systemName: "chevron.left", label: "Back") {
                dismiss()
            }

            Button {
                openProfile(post.authorName, colorHex: post.authorColorHex,
                            door: .author(post.persistentModelID))
            } label: {
                HStack(spacing: 10) {
                    AvatarCircle(initials: post.initials, tone: PersonTone.from(hex: post.authorColorHex), size: 38,
                                 photo: members.photo(forAuthor: post.authorName))
                        .matchedTransitionSource(id: ZoomID.author(post.persistentModelID), in: zoom)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(post.authorName)
                            .plName()
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                        Text(post.dishTitle.isEmpty ? "Open ask" : post.dishTitle)
                            .plType(.caption, .semibold)
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            Spacer()
            AccountButton()
            if post.kind == "dish" {
                if recipes.contains(where: { $0.originID == post.originKey }) {
                    // A receipt, not a button — same state the feed shows.
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text("Saved")
                            .plType(.footnote, .bold)
                    }
                    .foregroundStyle(Color.inkSecondary)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Already in your cookbook")
                } else {
                    Button {
                        save()
                    } label: {
                        Text("Save")
                            .plType(.footnote, .bold)
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
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
                TableReactions.vote(post, option: index)
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
                    .foregroundStyle(mine ? Color.basil : Color.inkSecondary)
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
        .accessibilityAddTraits(mine ? .isSelected : [])
    }

    private func commentKey(_ comment: TableComment) -> String { comment.shareRecordName.isEmpty ? String(describing: comment.persistentModelID) : comment.shareRecordName }

    /// Linearized tree with bounded indentation. Missing parents and cycles
    /// remain visible; stale sync data can never hide someone's comment.
    private var threadRows: [(comment: TableComment, depth: Int)] {
        let comments = post.sortedComments
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
            for child in post.sortedComments where child.parentCommentID == parent {
                if visited.insert(child.shareRecordName).inserted { visit(child.shareRecordName) }
            }
        }
        visit(id)
        return visited.count - 1
    }

    private func threadComment(_ comment: TableComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                openProfile(comment.authorName, door: .author(comment.persistentModelID))
            } label: {
                AvatarCircle(initials: initials(for: comment.authorName), tone: tone(for: comment.authorName), size: 30,
                             photo: members.photo(forAuthor: comment.authorName))
                    .matchedTransitionSource(id: ZoomID.author(comment.persistentModelID), in: zoom)
            }
            .buttonStyle(.pressable)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Button {
                        openProfile(comment.authorName, door: .author(comment.persistentModelID))
                    } label: {
                        Text(comment.authorName)
                            .plName()
                            .plType(.footnote, .bold)
                            .foregroundStyle(Color.ink)
                    }
                    .buttonStyle(.pressable)
                    if !comment.replyToName.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(.system(size: 8))
                            Text(comment.replyToName)
                                .plType(.micro)
                        }
                        .foregroundStyle(Color.inkSecondary)
                    }
                    Text(relativeWhen(comment.createdAt))
                        .plType(.micro, .medium)
                        .foregroundStyle(Color.inkSecondary)
                }
                if comment.deletedAt != nil {
                    Text("Comment deleted").plType(.body).foregroundStyle(Color.inkSecondary)
                } else { mentionedText(comment).lineSpacing(2) }
                if let data = comment.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 200, maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
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
                        .foregroundStyle(Color.tomato)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(Color.chipFill, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.navHairline))
                    }
                }
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
                        .foregroundStyle(Color.inkSecondary)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
            Spacer(minLength: 0)
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
        .modifier(CommentActions(comment: comment, canRemove: canRemove(comment)) {
            remove(comment)
        })
    }

    /// Your own comment, or any comment on your own post.
    private func canRemove(_ comment: TableComment) -> Bool {
        let me = members.first(where: \.isOwner)?.name ?? userFirstName
        guard !me.isEmpty, comment.deletedAt == nil else { return false }
        return comment.authorName == me || post.authorName == me
    }

    private func remove(_ comment: TableComment) {
        Haptic.warn()
        withAnimation(.plSnap) {
            comment.deletedAt = .now
            comment.text = ""
            comment.linkURL = ""
            comment.photoData = nil
            comment.mentions = []
        }
        Persist.save(context, "delete comment")
        TableOutbox.shared.enqueue(.note(post: post.shareRecordName, zoneOwner: post.shareZoneOwner, id: comment.shareRecordName), author: TableIdentity.cached)
        Task {
            if await TableShare.pushNote(comment, post: post.shareRecordName, zoneOwner: post.shareZoneOwner) {
                TableOutbox.shared.remove("note:" + comment.shareRecordName)
            }
        }
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
        let plain = Font.jakarta(TypeScale.body.size)
        let bold = Font.jakarta(TypeScale.body.size, .bold)
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
                            .foregroundStyle(Color.inkFaint)
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
                                        .foregroundStyle(Color.ink)
                                }
                                .padding(.horizontal, 10)
                                .frame(minHeight: 34)
                                .overlay(Capsule().strokeBorder(Color.hairline))
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
                    .frame(height: 40)
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

            HStack(spacing: 6) {
                Button {
                    Haptic.tap()
                    withAnimation(.plSnap) { mentionBarShown.toggle() }
                } label: {
                    Image(systemName: "at")
                        .accessibilityLabel("Mention someone")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(mentionBarShown ? Color.ink : Color.inkFaint)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo")
                        .accessibilityLabel("Add a photo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(commentPhoto == nil ? Color.inkFaint : Color.ink)
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
                        .foregroundStyle(linkFieldShown ? Color.ink : Color.inkFaint)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)

                TextField(placeholder, text: $draft, axis: .vertical)
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
                        .fill(canSend ? Color.tomato : Color.fill)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "arrow.up")
                                .accessibilityLabel("Send")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(canSend ? Color.onTomato : Color.inkFaint)
                        }
                        .plTapTarget()
                }
                .buttonStyle(.pressable)
                .disabled(!canSend)
            }
            .padding(.horizontal, 20)
            // The floating tab bar rides over pushed pages — the composer
            // clears it. Derived, not hand-typed: the 92 that used to sit
            // here put the send button squarely under Prongsby's perch,
            // so tapping send opened him instead of posting the comment.
            //
            // But only while the keyboard is down. Raised, the keyboard
            // already covers the bar and the perch, so holding the clearance
            // stranded the composer 84pt above the keys with a band of empty
            // canvas under it — the one moment the bar is guaranteed not to
            // be in the way is the one moment it was still being avoided.
            .padding(.bottom, composerFocused ? 10 : Layout.tabBarInset)
            .animation(.plSnap, value: composerFocused)
        }
    }

    private var placeholder: String {
        if replyTo != nil { return "Your reply…" }
        return post.kind == "ask" ? "Suggest a dish…" : "Add a comment…"
    }

    private var canSend: Bool {
        // The link field is there so a comment can BE a link. Requiring
        // text as well made it decoration.
        !draft.isEmpty || commentPhoto != nil
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
        .background(Color.canvas, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.navHairline))
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

    private func send() {
        let author = userFirstName.isEmpty
            ? (members.first(where: \.isOwner)?.name ?? "Me")
            : userFirstName
        let normalized = link.isEmpty ? "" : (link.hasPrefix("http") ? link : "https://\(link)")
        let mentioned = members.map(\.name).filter { draft.contains("@\($0)") }
        let comment = TableComment(
            authorName: author,
            // Not a camera emoji. `canSend` deliberately allows a comment
            // that is only a link, and this stamped every one of them with
            // a 📷 in the body — so a pasted recipe URL rendered as a
            // photograph that was not there. An empty body with a link or a
            // photo carrying the row is a valid comment and every renderer
            // already handles it.
            text: draft,
            linkURL: normalized,
            replyToName: replyTo ?? "",
            mentions: mentioned,
            photoData: commentPhoto,
            authorID: TableIdentity.cached
        )
        comment.parentCommentID = replyToID
        comment.post = post
        context.insert(comment)
        // Out to the table. Not awaited: the comment is already on screen
        // and already saved, and a slow upload must never hold the composer.
        // A refusal leaves it queued rather than lost.
        let postRecord = post.shareRecordName
        let zoneOwner = post.shareZoneOwner
        Task {
            if await TableShare.pushNote(comment, post: postRecord, zoneOwner: zoneOwner) == false {
                TableOutbox.shared.enqueue(
                    .note(post: postRecord, zoneOwner: zoneOwner, id: comment.shareRecordName),
                    author: comment.authorID
                )
            }
        }
        if post.authorName != author && post.firstName != author {
            Notifier.post(
                .commentAdded, actor: author,
                body: replyTo == nil
                    ? "\(author) commented on \(post.firstName)'s \(post.dishTitle.isEmpty ? "post" : post.dishTitle)."
                    : "\(author) replied to \(replyTo ?? "") on \(post.firstName)'s post.",
                into: context
            )
        }
        Haptic.plate()
        draft = ""
        link = ""
        linkFieldShown = false
        commentPhoto = nil
        photoItem = nil
        withAnimation(.plSnap) { replyTo = nil; replyToID = nil }
    }

    private func openProfile(_ name: String, colorHex: String? = nil, door: ZoomID) {
        Haptic.tap()
        personDoor = door
        let hex = colorHex
            ?? members.first { $0.name == name || name.hasPrefix($0.name) }?.colorHex
            ?? "FF5A3C"
        personShown = PersonRef.author(name, colorHex: hex, in: members)
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
    let remove: () -> Void

    func body(content: Content) -> some View {
        if canRemove {
            SwipeRow(isOpen: .constant(false), actions: [.remove(remove)]) {
                content
            }
            .contextMenu {
                Button(role: .destructive, action: remove) {
                    Label("Delete comment", systemImage: "trash")
                }
            }
        } else {
            content
        }
    }
}
