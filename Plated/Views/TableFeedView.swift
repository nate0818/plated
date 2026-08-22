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
    @State private var threadPost: TablePost?
    @State private var seatsPresented = false
    @State private var savedToast: String?
    @State private var toastToken = 0
    @State private var discoverPresented = false
    @AppStorage("pendingSeats") private var pendingSeatsRaw = ""

    private var seatCount: Int {
        // "Sam Meadows" the author is "Sam" the household member — first
        // names bridge the two worlds until real user IDs exist.
        let knownNames = Set(members.map(\.name))
        let guests = Set(
            posts.filter { $0.kind == "dish" }
                .map(\.authorName)
                .filter { !knownNames.contains($0) && !knownNames.contains(String($0.split(separator: " ").first ?? "")) }
        )
        let pending = pendingSeatsRaw.split(separator: "\n").filter { !$0.isEmpty }.count
        return max(members.count + guests.count + pending, 1)
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
        .sheet(item: $threadPost) { post in
            PostThreadView(post: post) { saveToCookbook($0) }
        }
        .sheet(isPresented: $seatsPresented) {
            TableSeatsSheet()
        }
        .fullScreenCover(isPresented: $discoverPresented) {
            DiscoverView()
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
                threadPost = posts.first { $0.kind == "dish" }
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.inkFaint)
                    MicroLabel("\(seatCount) seats · Invite only")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text("The Table")
                    .font(.gabarito(25, .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.ink)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
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
            // The seats at your table — tap to see, message, and manage them.
            Button {
                Haptic.tap()
                seatsPresented = true
            } label: {
                HStack(spacing: -8) {
                    ForEach(Array(members.filter { !$0.isOwner }.prefix(2)), id: \.persistentModelID) { member in
                        AvatarCircle(initials: member.firstInitial, tone: member.tone, size: 34)
                            .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 2))
                    }
                    AvatarCircle(initials: "+\(max(seatCount - 3, 1))", tone: .tomatoPair, size: 34)
                        .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 2))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                    // The photo is the door to the thread.
                    Button {
                        Haptic.tap()
                        threadPost = post
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                            .plCardShadow()
                    }
                    .buttonStyle(.plain)
                }
                if post.hasChefsKiss {
                    chefsKissPill
                        .offset(x: 6, y: -10)
                        .transition(.scale(scale: 0.01).combined(with: .opacity))
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
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.inkSecondary)
                        Text("\(post.sortedComments.count)")
                            .font(.jakarta(14, .bold))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                threadPost = post
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
                threadPost = post
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
                PlateReactionGlyph(filled: post.platedByMe)
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
    /// photo and all, ready to land on a night. The author gets the credit —
    /// a save is the sincerest form of dinner flattery.
    private func saveToCookbook(_ post: TablePost) {
        Haptic.plate()
        let title = post.dishTitle.isEmpty ? "From \(post.firstName)'s table" : post.dishTitle
        if !recipes.contains(where: { $0.originID == post.originKey }) {
            let recipe = Recipe(title: title, summary: post.caption)
            recipe.photoData = post.photoData
            recipe.tags = ["From the Table"]
            recipe.originID = post.originKey
            context.insert(recipe)
            // Local ledger today; becomes a real push to the author when the
            // network arrives. Counted once per dish, like the save itself.
            Awards.recordSaveReceived(by: post.authorName)
        }
        toastToken += 1
        let token = toastToken
        withAnimation(.plSnap) { savedToast = "Saved — \(post.firstName) gets the credit" }
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

/// The plate reaction mark. At rest it is an actual plate — rim outside,
/// well inside — so nobody mistakes it for an empty radio button; filled,
/// it goes tomato with the well knocked out in canvas.
struct PlateReactionGlyph: View {
    var filled: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(filled ? Color.tomato : Color.inkSecondary, lineWidth: 2)
                .background(Circle().fill(filled ? Color.tomato : Color.clear))
                .frame(width: 26, height: 26)
            if filled {
                Circle()
                    .fill(Color.canvas)
                    .frame(width: 9, height: 9)
            } else {
                Circle()
                    .strokeBorder(Color.inkSecondary, lineWidth: 1.5)
                    .frame(width: 13, height: 13)
            }
        }
    }
}

/// The same reaction, self-contained for the thread view.
struct PlateReactionButton: View {
    let post: TablePost
    @Binding var bounce: Bool

    var body: some View {
        Button {
            let turningOn = !post.platedByMe
            withAnimation(.plPop) {
                post.platedByMe.toggle()
                bounce = true
            }
            if turningOn {
                post.hasChefsKiss ? Haptic.kiss() : Haptic.plate()
            } else {
                Haptic.tap()
            }
            Task {
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.plSnap) { bounce = false }
            }
        } label: {
            PlateReactionGlyph(filled: post.platedByMe)
                .scaleEffect(bounce ? 1.35 : 1)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}
