import SwiftUI
import SwiftData
import PhotosUI

/// One post, opened into a page — photo big, every comment threaded below,
/// the composer pinned. Replies point at people, @ mentions ring the
/// household, photos land in the talk, and every name is a door to a
/// profile. The back chevron is always top-left; no sheet to guess at.
struct PostThreadView: View {
    let post: TablePost
    /// Provided by the feed (which owns its toast); when nil — a thread
    /// opened from a profile page — the thread runs the save flow itself.
    var onSave: ((TablePost) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userFirstName") private var userFirstName = ""
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var recipes: [Recipe]

    @State private var draft = ""
    @State private var link = ""
    @State private var linkFieldShown = false
    @State private var replyTo: String?
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
                            PhotoWell(image: image, height: 320)
                                .plCardShadow()
                            if post.hasChefsKiss {
                                chefsKissPill.offset(x: 6, y: -10)
                            }
                        }
                    }

                    HStack(spacing: 14) {
                        PlateReactionButton(post: post, bounce: $bounce)
                        Text(post.totalPlates == 1 ? "1 plate" : "\(post.totalPlates) plates")
                            .plType(.footnote, .semibold)
                            .foregroundStyle(Color.inkSecondary)
                        Spacer()
                    }

                    // Spelled out because concatenated Text takes a Font,
                    // not a view modifier. TypeScale.body's numbers.
                    (Text(post.authorName).font(.jakarta(TypeScale.body.size, .bold))
                     + Text("  ").font(.jakarta(TypeScale.body.size))
                     + Text(post.caption).font(.jakarta(TypeScale.body.size)))
                        .foregroundStyle(Color.ink)
                        .lineSpacing(3)

                    if !post.taggedNames.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(post.taggedNames, id: \.self) { name in
                                Button {
                                    openProfile(name)
                                } label: {
                                    // The whole target was the glyph box:
                                    // about 22 by 14 points for a short
                                    // name. It is a chip inside a 44pt
                                    // frame now, the same two-frame shape
                                    // the Save pill above it uses.
                                    Text("@\(name)")
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

                    MicroLabel("Comments · \(post.sortedComments.count)")
                        .padding(.top, 8)

                    if post.sortedComments.isEmpty {
                        Text(post.kind == "ask" ? "No suggestions yet" : "No comments yet")
                            .plType(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                    }

                    ForEach(post.sortedComments, id: \.persistentModelID) { comment in
                        threadComment(comment)
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
        .toolbar(.hidden, for: .navigationBar)
        // This page docks its own composer at the bottom-trailing corner,
        // exactly where the perch lives.
        .hidesProngsbyPerch()
        .plSwipeBack()
        .navigationDestination(item: $personShown) { person in
            PersonProfileView(personName: person.name, colorHex: person.colorHex, memberID: person.memberID)
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
                    body: "\(me) saved \(post.firstName)'s \(post.dishTitle.isEmpty ? "dish" : post.dishTitle). They get the credit.",
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
                openProfile(post.authorName, colorHex: post.authorColorHex)
            } label: {
                HStack(spacing: 10) {
                    AvatarCircle(initials: post.initials, tone: PersonTone.from(hex: post.authorColorHex), size: 38,
                                 photo: members.photo(forAuthor: post.authorName))
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
        let mine = post.myPollChoice == index
        return Button {
            Haptic.plate()
            withAnimation(.plSnap) {
                post.myPollChoice = mine ? -1 : index
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
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(mine ? Color.basilTint : Color.hairlineSoft)
                        .frame(width: max(proxy.size.width * fraction, votes > 0 ? 20 : 0))
                        .animation(.plSnap, value: fraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(mine ? Color.basil.opacity(0.4) : Color.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(mine ? .isSelected : [])
    }

    private func threadComment(_ comment: TableComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                openProfile(comment.authorName)
            } label: {
                AvatarCircle(initials: initials(for: comment.authorName), tone: tone(for: comment.authorName), size: 30,
                             photo: members.photo(forAuthor: comment.authorName))
            }
            .buttonStyle(.pressable)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Button {
                        openProfile(comment.authorName)
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
                mentionedText(comment)
                    .lineSpacing(2)
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
    }

    /// Renders @mentions ink-bold so they read as names, not alarms.
    private func mentionedText(_ comment: TableComment) -> Text {
        var result = Text("")
        for word in comment.text.split(separator: " ", omittingEmptySubsequences: false) {
            let piece = String(word)
            if piece.hasPrefix("@"), comment.mentions.contains(where: { piece.dropFirst().hasPrefix($0) }) {
                result = result + Text(piece).font(.jakarta(TypeScale.body.size, .bold)).foregroundStyle(Color.ink)
            } else {
                result = result + Text(piece).font(.jakarta(TypeScale.body.size)).foregroundStyle(Color.ink)
            }
            result = result + Text(" ")
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
                        withAnimation(.plSnap) { self.replyTo = nil }
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
                    .plType(.footnote)
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
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .padding(.bottom, Layout.tabBarInset)
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

    private func send() {
        let author = userFirstName.isEmpty
            ? (members.first(where: \.isOwner)?.name ?? "Me")
            : userFirstName
        let normalized = link.isEmpty ? "" : (link.hasPrefix("http") ? link : "https://\(link)")
        let mentioned = members.map(\.name).filter { draft.contains("@\($0)") }
        let comment = TableComment(
            authorName: author,
            text: draft.isEmpty ? "📷" : draft,
            linkURL: normalized,
            replyToName: replyTo ?? "",
            mentions: mentioned,
            photoData: commentPhoto
        )
        comment.post = post
        context.insert(comment)
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
        withAnimation(.plSnap) { replyTo = nil }
    }

    private func openProfile(_ name: String, colorHex: String? = nil) {
        Haptic.tap()
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
