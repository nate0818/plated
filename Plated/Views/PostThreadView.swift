import SwiftUI
import SwiftData

/// One post, opened up — the photo big, every comment in a forum-style
/// thread below it, and the composer always in reach. Tapping the photo or
/// the comment count anywhere in the feed lands here.
struct PostThreadView: View {
    let post: TablePost
    var onSave: (TablePost) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userFirstName") private var userFirstName = ""
    @Query private var members: [HouseholdMember]

    @State private var draft = ""
    @State private var link = ""
    @State private var linkFieldShown = false
    @State private var bounce = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 12)
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 10) {
            AvatarCircle(initials: post.initials, tone: PersonTone.from(hex: post.authorColorHex), size: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(post.authorName)
                    .font(.jakarta(15, .bold))
                    .foregroundStyle(Color.ink)
                Text(post.dishTitle.isEmpty ? "Open ask" : post.dishTitle)
                    .font(.jakarta(12, .semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
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
    }

    private func threadComment(_ comment: TableComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarCircle(initials: initials(for: comment.authorName), tone: .neutralPair, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.jakarta(13, .bold))
                        .foregroundStyle(Color.ink)
                    Text(relativeWhen(comment.createdAt))
                        .font(.jakarta(11, .medium))
                        .foregroundStyle(Color.inkFaint)
                }
                Text(comment.text)
                    .font(.jakarta(14))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(2)
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
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            Divider().overlay(Color.hairlineSoft)
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
            HStack(spacing: 10) {
                Button {
                    Haptic.tap()
                    withAnimation(.plSnap) { linkFieldShown.toggle() }
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(linkFieldShown ? Color.tomato : Color.inkSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)

                TextField(post.kind == "ask" ? "Suggest a dish…" : "Say something nice…", text: $draft, axis: .vertical)
                    .font(.jakarta(14, .medium))
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))

                Button {
                    send()
                } label: {
                    Circle()
                        .fill(draft.isEmpty ? Color.fill : Color.tomato)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(draft.isEmpty ? Color.inkFaint : .white)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(draft.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
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
        let comment = TableComment(authorName: author, text: draft, linkURL: normalized)
        comment.post = post
        context.insert(comment)
        Haptic.plate()
        draft = ""
        link = ""
        linkFieldShown = false
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
