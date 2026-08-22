import SwiftUI
import SwiftData
import PhotosUI

/// One post, opened into a page — photo big, every comment threaded below,
/// the composer pinned. Replies point at people, @ mentions ring the
/// household, photos land in the talk, and every name is a door to a
/// profile. The back chevron is always top-left; no sheet to guess at.
struct PostThreadView: View {
    let post: TablePost
    var onSave: (TablePost) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userFirstName") private var userFirstName = ""
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @State private var draft = ""
    @State private var link = ""
    @State private var linkFieldShown = false
    @State private var replyTo: String?
    @State private var mentionBarShown = false
    @State private var photoItem: PhotosPickerItem?
    @State private var commentPhoto: Data?
    @State private var bounce = false
    @State private var personShown: PersonRef?
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Color.hairlineSoft)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let data = post.photoData, let image = UIImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 320)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                                .plCardShadow()
                            if post.hasChefsKiss {
                                chefsKissPill.offset(x: 6, y: -10)
                            }
                        }
                    }

                    HStack(spacing: 14) {
                        PlateReactionButton(post: post, bounce: $bounce)
                        Text(post.totalPlates == 1 ? "1 plate" : "\(post.totalPlates) plates")
                            .font(.jakarta(13, .semibold))
                            .foregroundStyle(Color.inkSecondary)
                        Spacer()
                    }

                    (Text(post.authorName).font(.jakarta(15, .bold))
                     + Text("  ").font(.jakarta(15))
                     + Text(post.caption).font(.jakarta(15)))
                        .foregroundStyle(Color.ink)
                        .lineSpacing(3)

                    if !post.taggedNames.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(post.taggedNames, id: \.self) { name in
                                Button {
                                    openProfile(name)
                                } label: {
                                    Text("@\(name)")
                                        .font(.jakarta(12, .bold))
                                        .foregroundStyle(Color.tomato)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                    }

                    if post.hasPoll {
                        pollCard
                    }

                    MicroLabel("Table talk · \(post.sortedComments.count)")
                        .padding(.top, 8)

                    if post.sortedComments.isEmpty {
                        Text(post.kind == "ask" ? "No suggestions yet — be the first." : "Nobody has said anything yet. Go on.")
                            .font(.jakarta(13, .medium))
                            .foregroundStyle(Color.inkFaint)
                    }

                    ForEach(post.sortedComments, id: \.persistentModelID) { comment in
                        threadComment(comment)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }

            composer
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $personShown) { person in
            PersonProfileView(personName: person.name, colorHex: person.colorHex)
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
            Button {
                Haptic.tap()
                dismiss()
            } label: {
                Circle()
                    .strokeBorder(Color.hairline, lineWidth: 1.5)
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

            Button {
                openProfile(post.authorName, colorHex: post.authorColorHex)
            } label: {
                HStack(spacing: 10) {
                    AvatarCircle(initials: post.initials, tone: PersonTone.from(hex: post.authorColorHex), size: 38)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(post.authorName)
                            .font(.jakarta(15, .bold))
                            .foregroundStyle(Color.ink)
                        Text(post.dishTitle.isEmpty ? "Open ask" : post.dishTitle)
                            .font(.jakarta(12, .semibold))
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            if post.kind == "dish" {
                Button {
                    onSave(post)
                } label: {
                    Text("Save")
                        .font(.jakarta(13, .bold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
            MicroLabel("The table votes")
            ForEach(Array(post.pollOptions.enumerated()), id: \.offset) { index, option in
                pollRow(index: index, option: option)
            }
            Text(post.totalPollVotes == 1 ? "1 vote" : "\(post.totalPollVotes) votes")
                .font(.jakarta(11, .semibold))
                .foregroundStyle(Color.inkFaint)
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
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
                Text(option)
                    .font(.jakarta(14, mine ? .bold : .semibold))
                    .foregroundStyle(Color.ink)
                Spacer()
                Text("\(votes)")
                    .font(.jakarta(13, .bold))
                    .foregroundStyle(mine ? Color.basil : Color.inkSecondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(mine ? Color.basilTint : Color.hairlineSoft)
                        .frame(width: max(proxy.size.width * fraction, votes > 0 ? 20 : 0))
                        .animation(.plSnap, value: fraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(mine ? Color.basil.opacity(0.4) : Color.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func threadComment(_ comment: TableComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                openProfile(comment.authorName)
            } label: {
                AvatarCircle(initials: initials(for: comment.authorName), tone: tone(for: comment.authorName), size: 30)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Button {
                        openProfile(comment.authorName)
                    } label: {
                        Text(comment.authorName)
                            .font(.jakarta(13, .bold))
                            .foregroundStyle(Color.ink)
                    }
                    .buttonStyle(.plain)
                    if !comment.replyToName.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(.system(size: 8))
                            Text(comment.replyToName)
                                .font(.jakarta(11, .bold))
                        }
                        .foregroundStyle(Color.inkFaint)
                    }
                    Text(relativeWhen(comment.createdAt))
                        .font(.jakarta(11, .medium))
                        .foregroundStyle(Color.inkFaint)
                }
                mentionedText(comment)
                    .lineSpacing(2)
                if let data = comment.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 200, maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.chip))
                        .padding(.top, 2)
                }
                if !comment.linkURL.isEmpty, let url = URL(string: comment.linkURL) {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .bold))
                            Text(comment.linkLabel)
                                .font(.jakarta(12, .bold))
                        }
                        .foregroundStyle(Color.tomato)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
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
                        .font(.jakarta(11, .bold))
                        .foregroundStyle(Color.inkFaint)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// Renders @mentions in tomato so they read as the links they are.
    private func mentionedText(_ comment: TableComment) -> Text {
        var result = Text("")
        for word in comment.text.split(separator: " ", omittingEmptySubsequences: false) {
            let piece = String(word)
            if piece.hasPrefix("@"), comment.mentions.contains(where: { piece.dropFirst().hasPrefix($0) }) {
                result = result + Text(piece).font(.jakarta(14, .bold)).foregroundStyle(Color.tomato)
            } else {
                result = result + Text(piece).font(.jakarta(14)).foregroundStyle(Color.ink)
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
                        .font(.jakarta(12, .bold))
                        .foregroundStyle(Color.inkSecondary)
                    Spacer()
                    Button {
                        withAnimation(.plSnap) { self.replyTo = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.inkFaint)
                            .frame(minWidth: 32, minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
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
                                    AvatarCircle(initials: member.firstInitial, tone: member.tone, size: 22)
                                    Text(member.name)
                                        .font(.jakarta(12, .bold))
                                        .foregroundStyle(Color.ink)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .overlay(Capsule().strokeBorder(Color.hairline))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }

            if linkFieldShown {
                TextField("Paste a link", text: $link)
                    .font(.jakarta(13, .medium))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
                    .padding(.horizontal, 24)
            }

            if let commentPhoto, let image = UIImage(data: commentPhoto) {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.plSnap) { self.commentPhoto = nil }
                            } label: {
                                Circle()
                                    .fill(Color.ink.opacity(0.7))
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                    .padding(2)
                            }
                            .buttonStyle(.plain)
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(mentionBarShown ? Color.tomato : Color.inkSecondary)
                        .frame(minWidth: 36, minHeight: 44)
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(commentPhoto == nil ? Color.inkSecondary : Color.tomato)
                        .frame(minWidth: 36, minHeight: 44)
                }
                .buttonStyle(.plain)

                Button {
                    Haptic.tap()
                    withAnimation(.plSnap) { linkFieldShown.toggle() }
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(linkFieldShown ? Color.tomato : Color.inkSecondary)
                        .frame(minWidth: 36, minHeight: 44)
                }
                .buttonStyle(.plain)

                TextField(placeholder, text: $draft, axis: .vertical)
                    .font(.jakarta(14, .medium))
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
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
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(canSend ? .white : Color.inkFaint)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 20)
            // The floating tab bar rides over pushed pages — the composer
            // clears it.
            .padding(.bottom, 92)
        }
    }

    private var placeholder: String {
        if replyTo != nil { return "Your reply…" }
        return post.kind == "ask" ? "Suggest a dish…" : "Say something nice…"
    }

    private var canSend: Bool { !draft.isEmpty || commentPhoto != nil }

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
        .frame(height: 36)
        .background(Color.canvas, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.navHairline))
        .shadow(color: Color.shadowInk.opacity(0.14), radius: 10, y: 8)
    }

    // MARK: Actions

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
                    ? "\(author) commented on \(post.firstName)'s \(post.dishTitle.isEmpty ? "ask" : post.dishTitle)."
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
        personShown = PersonRef(name: name, colorHex: hex)
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
