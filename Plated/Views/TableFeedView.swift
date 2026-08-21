import SwiftUI
import SwiftData

/// The Table — the private feed. Reactions are plates; ten plates and the
/// dish earns its chef's kiss. Comments carry links because recipes live
/// all over the internet.
struct TableFeedView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<TablePost> { !$0.isDiscover },
        sort: \TablePost.createdAt, order: .reverse
    ) private var posts: [TablePost]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var recipes: [Recipe]

    @State private var bouncePost: PersistentIdentifier?
    @State private var commentingPost: TablePost?
    @State private var savedToast: String?
    @State private var toastToken = 0
    @State private var discoverPresented = false
    @AppStorage("pendingSeats") private var pendingSeatsRaw = ""

    private var seatCount: Int {
        let authors = Set(posts.filter { $0.kind == "dish" }.map(\.authorName))
        let pending = pendingSeatsRaw.split(separator: "\n").count
        return max(members.count + authors.subtracting(members.map(\.name)).count + pending, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 12)
            Divider().overlay(Color.hairlineSoft)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(posts) { post in
                        if post.kind == "ask" {
                            askCard(post)
                        } else {
                            postCard(post)
                        }
                        Divider().overlay(Color.hairlineSoft)
                    }
                }
                .padding(.bottom, 110)
            }
        }
        .sheet(item: $commentingPost) { post in
            CommentSheet(post: post)
        }
        .fullScreenCover(isPresented: $discoverPresented) {
            DiscoverView()
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-plated-open-discover") {
                discoverPresented = true
            }
            #endif
        }
        .overlay(alignment: .bottom) {
            if let toast = savedToast {
                Text(toast)
                    .font(.jakarta(13, .bold))
                    .foregroundStyle(Color.canvas)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Color.ink, in: Capsule())
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.inkFaint)
                    MicroLabel("\(seatCount) seats · Invite only")
                }
                Text("The Table")
                    .font(.gabarito(25, .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.ink)
            }
            Spacer()
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
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            HStack(spacing: -8) {
                ForEach(Array(members.filter { !$0.isOwner }.prefix(2)), id: \.persistentModelID) { member in
                    AvatarCircle(initials: member.firstInitial, tone: member.tone, size: 34)
                        .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 2))
                }
                AvatarCircle(initials: "+\(max(seatCount - 3, 1))", tone: .tomatoPair, size: 34)
                    .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 2))
            }
        }
    }

    // MARK: Cards

    private func postCard(_ post: TablePost) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AvatarCircle(initials: post.initials, tone: PersonTone.from(hex: post.authorColorHex), size: 38)
                VStack(alignment: .leading, spacing: 0) {
                    Text(post.authorName)
                        .font(.jakarta(14, .bold))
                        .foregroundStyle(Color.ink)
                    Text(postWhen(post.createdAt))
                        .font(.jakarta(11, .semibold))
                        .foregroundStyle(Color.inkFaint)
                }
                Spacer()
                Button {
                    saveToCookbook(post)
                } label: {
                    Text("Save")
                        .font(.jakarta(13, .bold))
                        .foregroundStyle(Color.ink)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            ZStack(alignment: .topTrailing) {
                if let data = post.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        .plCardShadow()
                }
                if post.hasChefsKiss {
                    chefsKissPill
                        .offset(x: 6, y: -10)
                        .transition(.scale(scale: 0.01).combined(with: .opacity))
                }
            }

            HStack(spacing: 14) {
                plateButton(post)
                HStack(spacing: 7) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.inkSecondary)
                    Text("\(post.sortedComments.count)")
                        .font(.jakarta(14, .bold))
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
            }
            .padding(.top, 10)

            (Text(post.authorName).font(.jakarta(14, .bold))
             + Text("  ").font(.jakarta(14))
             + Text(post.caption).font(.jakarta(14)))
                .foregroundStyle(Color.ink)
                .lineSpacing(3)
                .padding(.top, 4)

            ForEach(post.sortedComments.prefix(2), id: \.persistentModelID) { comment in
                commentLine(comment)
            }

            Button {
                commentingPost = post
            } label: {
                Text("Add a comment for \(post.firstName)…")
                    .font(.jakarta(12, .semibold))
                    .foregroundStyle(Color.inkFaint)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .animation(.plPop, value: post.hasChefsKiss)
    }

    private func askCard(_ post: TablePost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarCircle(initials: post.initials, tone: PersonTone.from(hex: post.authorColorHex), size: 38)
                VStack(alignment: .leading, spacing: 0) {
                    Text(post.authorName)
                        .font(.jakarta(14, .bold))
                        .foregroundStyle(Color.ink)
                    Text(postWhen(post.createdAt))
                        .font(.jakarta(11, .semibold))
                        .foregroundStyle(Color.inkFaint)
                }
                Spacer()
                MicroLabel("Open ask")
            }
            Text(post.caption)
                .font(.jakarta(15, .semibold))
                .foregroundStyle(Color.ink)
                .lineSpacing(3)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.row)
                        .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                }
            ForEach(post.sortedComments, id: \.persistentModelID) { comment in
                commentLine(comment)
            }
            Button {
                commentingPost = post
            } label: {
                Text("Suggest a dish…")
                    .font(.jakarta(12, .semibold))
                    .foregroundStyle(Color.inkFaint)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
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

    private func plateButton(_ post: TablePost) -> some View {
        Button {
            togglePlate(post)
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .strokeBorder(post.platedByMe ? Color.tomato : Color.inkSecondary, lineWidth: 2)
                        .background(Circle().fill(post.platedByMe ? Color.tomato : Color.clear))
                        .frame(width: 26, height: 26)
                    if post.platedByMe {
                        Circle()
                            .fill(Color.canvas)
                            .frame(width: 9, height: 9)
                    }
                }
                .scaleEffect(bouncePost == post.persistentModelID ? 1.35 : 1)
                Text("\(post.totalPlates)")
                    .font(.jakarta(14, .bold))
                    .foregroundStyle(post.platedByMe ? Color.tomato : Color.inkSecondary)
                    .contentTransition(.numericText())
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private func commentLine(_ comment: TableComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text(comment.authorName).font(.jakarta(13, .bold)).foregroundStyle(Color.ink)
             + Text("  ").font(.jakarta(13))
             + Text(comment.text).font(.jakarta(13)).foregroundStyle(Color.inkSecondary))
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

    /// "Plate it" pulls the dish home: the post becomes a cookbook recipe,
    /// photo and all, ready to land on a night.
    private func saveToCookbook(_ post: TablePost) {
        Haptic.plate()
        let title = post.dishTitle.isEmpty ? "From \(post.firstName)'s table" : post.dishTitle
        if !recipes.contains(where: { $0.originID == post.originKey }) {
            let recipe = Recipe(title: title, summary: post.caption)
            recipe.photoData = post.photoData
            recipe.tags = ["From the Table"]
            recipe.originID = post.originKey
            context.insert(recipe)
        }
        toastToken += 1
        let token = toastToken
        withAnimation(.plSnap) { savedToast = "Saved to your cookbook" }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toastToken == token {
                withAnimation(.plSnap) { savedToast = nil }
            }
        }
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

/// Comments allow URLs on purpose. Grandma has links.
struct CommentSheet: View {
    let post: TablePost

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userFirstName") private var userFirstName = ""
    @Query private var members: [HouseholdMember]

    @State private var text = ""
    @State private var link = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("For \(post.firstName)")
                .font(.gabarito(19, .extraBold))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

            TextField("Say something nice…", text: $text, axis: .vertical)
                .font(.jakarta(15, .medium))
                .lineLimit(3...6)
                .padding(14)
                .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))

            TextField("Add a link (optional)", text: $link)
                .font(.jakarta(14, .medium))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))

            TomatoPillButton(title: "Send to the table") {
                let author = userFirstName.isEmpty
                    ? (members.first(where: \.isOwner)?.name ?? "Me")
                    : userFirstName
                let comment = TableComment(authorName: author, text: text, linkURL: normalizedLink)
                comment.post = post
                context.insert(comment)
                dismiss()
            }
            .disabled(text.isEmpty)
            .opacity(text.isEmpty ? 0.4 : 1)
            Spacer()
        }
        .padding(.horizontal, 24)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    private var normalizedLink: String {
        guard !link.isEmpty else { return "" }
        return link.hasPrefix("http") ? link : "https://\(link)"
    }
}
