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
    @State private var editingSave: TablePost?
    @State private var savedToast: String?
    @State private var toastToken = 0
    @State private var discoverPresented = false
    @State private var activityShown = false
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

    private var shownPosts: [TablePost] {
        guard scope == .household else { return posts }
        let names = Set(members.map(\.name))
        return posts.filter { names.contains($0.firstName) || names.contains($0.authorName) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                scopePicker
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                Divider().overlay(Color.hairlineSoft)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(shownPosts, id: \.persistentModelID) { post in
                            if post.kind == "ask" {
                                askCard(post)
                            } else {
                                postCard(post)
                            }
                            Divider().overlay(Color.hairlineSoft)
                        }
                        if shownPosts.isEmpty {
                            VStack(spacing: 8) {
                                PlateReactionGlyph(filled: false)
                                    .plBreathing()
                                Text(scope == .household ? "The household hasn't posted yet." : "Nothing on the table yet.")
                                    .font(.jakarta(14, .bold))
                                    .foregroundStyle(Color.inkSecondary)
                            }
                            .padding(.top, 60)
                        }
                    }
                    .padding(.bottom, 110)
                }
            }
            .background(Color.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $threadPost) { post in
                PostThreadView(post: post) { beginSave($0) }
            }
            .navigationDestination(item: $personShown) { person in
                PersonProfileView(personName: person.name, colorHex: person.colorHex)
            }
            .navigationDestination(isPresented: $activityShown) {
                NotificationsView()
            }
        }
        .sheet(isPresented: $seatsPresented) {
            TableSeatsSheet()
        }
        .sheet(item: $editingSave) { post in
            RecipeEditorView(prefill: (
                title: post.dishTitle.isEmpty ? "From \(post.firstName)'s table" : post.dishTitle,
                summary: post.caption,
                photo: post.photoData,
                originID: post.originKey
            )) { _ in
                finishSave(post)
            }
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
                    .font(.gabarito(25, .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.ink)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            ActivityBellButton {
                activityShown = true
            }
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
            .buttonStyle(.pressable)
        }
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
                                    .shadow(color: Color.shadowWarm.opacity(0.12), radius: 4, y: 2)
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
                        AvatarCircle(initials: post.initials, tone: PersonTone.from(hex: post.authorColorHex), size: 38)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(post.authorName)
                                .font(.jakarta(14, .bold))
                                .foregroundStyle(Color.ink)
                            Text(postWhen(post.createdAt))
                                .font(.jakarta(11, .semibold))
                                .foregroundStyle(Color.inkFaint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                Spacer()
                Button {
                    beginSave(post)
                } label: {
                    Text("Save")
                        .font(.jakarta(13, .bold))
                        .foregroundStyle(Color.ink)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.pressable)
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
                    .buttonStyle(.pressable)
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
                .buttonStyle(.pressable)
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
                Haptic.tap()
                threadPost = post
            } label: {
                Text(post.sortedComments.count > 2
                     ? "See all \(post.sortedComments.count) comments"
                     : "Add a comment for \(post.firstName)…")
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
    }

    private func askCard(_ post: TablePost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    openProfile(post)
                } label: {
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
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                Spacer()
                MicroLabel(post.hasPoll ? "Poll" : "Open ask")
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
                            Text("\(post.pollOptions.count) choices · \(post.totalPollVotes) votes — tap to vote")
                                .font(.jakarta(12, .bold))
                        }
                        .foregroundStyle(Color.basil)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.row)
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
        // The author gets the credit — a save is the sincerest form of
        // dinner flattery. Local ledger today, real push later.
        Awards.recordSaveReceived(by: post.authorName)
        let me = members.first(where: \.isOwner)?.name ?? "Someone"
        Notifier.post(
            .saveReceived, actor: me,
            body: "\(me) saved \(post.firstName)'s \(post.dishTitle.isEmpty ? "dish" : post.dishTitle) — they get the credit.",
            into: context
        )
        showToast("Saved — \(post.firstName) gets the credit")
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
        personShown = PersonRef(name: post.authorName, colorHex: post.authorColorHex)
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
                .scaleEffect(bounce ? 1.35 : 1)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.pressable)
    }
}
