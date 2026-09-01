import SwiftUI
import SwiftData

/// Discover — dinners from tables that chose to be open. You go looking;
/// nothing here ever leaks in the other direction. Your table stays yours.
struct DiscoverView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<TablePost> { $0.isDiscover },
        sort: \TablePost.createdAt, order: .reverse
    ) private var posts: [TablePost]

    @State private var query = ""
    @State private var selected: TablePost?

    private var filtered: [TablePost] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return posts }
        return posts.filter {
            $0.dishTitle.localizedCaseInsensitiveContains(trimmed)
                || $0.authorName.localizedCaseInsensitiveContains(trimmed)
                || $0.caption.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    Haptic.tap()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                VStack(alignment: .leading, spacing: 2) {
                    MicroLabel("From open tables")
                    Text("Discover")
                        .font(.gabarito(25, .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.ink)
                }
                Spacer()
            }
            .padding(.leading, 12)
            .padding(.trailing, 24)
            .padding(.top, 6)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.inkFaint)
                TextField("Search dishes and tables", text: $query)
                    .font(.jakarta(15, .medium))
                    .foregroundStyle(Color.ink)
                    .tint(Color.tomato)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .accessibilityLabel("Clear search")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.inkFaint)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Color.chipFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.navHairline))
            .padding(.horizontal, 24)
            .padding(.top, 14)

            if filtered.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                        .plBreathing()
                    Text("No table is serving that")
                        .font(.jakarta(15, .bold))
                        .foregroundStyle(Color.inkSecondary)
                    Text("Try a dish, an ingredient, or a table's name.")
                        .font(.jakarta(13, .medium))
                        .foregroundStyle(Color.inkFaint)
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 20) {
                        ForEach(filtered, id: \.persistentModelID) { post in
                            tile(post)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                    HStack(spacing: 6) {
                        Image(systemName: "lock")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Open tables share with everyone. Yours stays invite-only.")
                            .font(.jakarta(12, .medium))
                    }
                    .foregroundStyle(Color.inkFaint)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
            }
        }
        .background(Color.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .plSwipeBack()
        .sheet(item: $selected) { post in
            DiscoverPostSheet(post: post)
        }
    }

    private func tile(_ post: TablePost) -> some View {
        Button {
            Haptic.tap()
            selected = post
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .frame(height: 190)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            if let data = post.photoData, let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.fill
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        .plCardShadow()
                    if post.hasChefsKiss {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.mango)
                            .frame(width: 28, height: 28)
                            .background(Color.canvas, in: Circle())
                            .overlay(Circle().strokeBorder(Color.navHairline))
                            .padding(8)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.dishTitle)
                        .font(.jakarta(13, .bold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(post.authorName)
                        .font(.jakarta(11, .semibold))
                        .foregroundStyle(Color.inkFaint)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}

/// One open-table dinner, up close. Plate it to react; save it to cook it.
struct DiscoverPostSheet: View {
    let post: TablePost

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var recipes: [Recipe]

    @State private var bounce = false
    @State private var saved = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            if let data = post.photoData, let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.fill
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.hero))
                        .plCardShadow()
                    if post.hasChefsKiss {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.mango)
                            Text("Chef's kiss")
                                .font(.jakarta(13, .bold))
                                .foregroundStyle(Color.ink)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Color.canvas, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.navHairline))
                        .shadow(color: Color.shadowInk.opacity(0.14), radius: 10, y: 8)
                        .offset(x: 6, y: -10)
                    }
                }

                HStack(spacing: 10) {
                    AvatarCircle(initials: post.initials, tone: PersonTone.from(hex: post.authorColorHex), size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(post.authorName)
                            .font(.jakarta(14, .bold))
                            .foregroundStyle(Color.ink)
                        Text("An open table")
                            .font(.jakarta(11, .semibold))
                            .foregroundStyle(Color.inkFaint)
                    }
                    Spacer()
                    Button {
                        togglePlate()
                    } label: {
                        HStack(spacing: 7) {
                            ZStack {
                                Circle()
                                    .strokeBorder(post.platedByMe ? Color.tomato : Color.inkSecondary, lineWidth: 2)
                                    .background(Circle().fill(post.platedByMe ? Color.tomato : Color.clear))
                                    .frame(width: 26, height: 26)
                                if post.platedByMe {
                                    Circle().fill(Color.canvas).frame(width: 9, height: 9)
                                }
                            }
                            .scaleEffect(bounce ? 1.35 : 1)
                            Text("\(post.totalPlates)")
                                .font(.jakarta(14, .bold))
                                .foregroundStyle(post.platedByMe ? Color.tomato : Color.inkSecondary)
                                .contentTransition(.numericText())
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.pressable)
                }

                Text(post.dishTitle)
                    .font(.gabarito(27, .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.ink)

                Text(post.caption)
                    .font(.jakarta(14, .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .lineSpacing(4)

                // The tomato budget here is spent on the plate reaction, so the
                // committing action takes the ink pill — and "plate" stays the
                // word for reactions and nights, never for saving.
                if saved {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                        Text("In your cookbook").font(.jakarta(16, .bold))
                    }
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                    .padding(.top, 6)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                } else {
                    InkPillButton(title: "Save to cookbook", systemImage: "book.closed") {
                        save()
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 36)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .onAppear {
            saved = recipes.contains { $0.originID == post.originKey }
        }
    }

    private func togglePlate() {
        let turningOn = !post.platedByMe
        withAnimation(.plPop) {
            post.platedByMe.toggle()
            bounce = true
        }
        turningOn ? (post.hasChefsKiss ? Haptic.kiss() : Haptic.plate()) : Haptic.tap()
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.plSnap) { bounce = false }
        }
    }

    private func save() {
        Haptic.plate()
        let recipe = Recipe(title: post.dishTitle, summary: post.caption)
        recipe.photoData = post.photoData
        recipe.tags = ["From \(post.authorName)"]
        recipe.originID = post.originKey
        context.insert(recipe)
        withAnimation(.plSnap) { saved = true }
    }
}
