import SwiftUI
import SwiftData
import PhotosUI

/// Post to the Table — the photo-first composer behind the +. A plated
/// moment: the photo, the dish's name, a line about it, and whoever helped.
struct TableComposerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoLoading = false
    @State private var dishTitle = ""
    @State private var caption = ""
    @State private var tagged: Set<String> = []

    /// A picked photo that is still resolving holds the post — a fast tap
    /// on the pill must never silently ship without it.
    private var canPost: Bool {
        !photoLoading &&
            (photoData != nil || !dishTitle.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Post to the Table")
                Text("What did you plate?")
                    .font(.gabarito(22, .extraBold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    photoWell

                    TextField("Name the dish — “Sunday Ragù”", text: $dishTitle)
                        .font(.jakarta(15, .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))

                    TextField("Say something about it — optional", text: $caption, axis: .vertical)
                        .font(.jakarta(15, .medium))
                        .lineLimit(2...4)
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))

                    if members.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            MicroLabel("Who helped")
                            // A big table overflows a plain row — the chips
                            // scroll sideways instead of walking off-screen.
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(members.filter { !$0.isOwner }, id: \.persistentModelID) { member in
                                        let active = tagged.contains(member.name)
                                        Button {
                                            Haptic.tap()
                                            withAnimation(.plSnap) {
                                                if active { tagged.remove(member.name) } else { tagged.insert(member.name) }
                                            }
                                        } label: {
                                            HStack(spacing: 5) {
                                                AvatarCircle(initials: member.firstInitial, tone: member.tone, size: 22)
                                                Text("@\(member.name)")
                                                    .font(.jakarta(12, .bold))
                                            }
                                            .foregroundStyle(active ? Color.canvas : Color.ink)
                                            .padding(.horizontal, 10)
                                            .frame(height: 36)
                                            .background {
                                                if active {
                                                    Capsule().fill(Color.ink)
                                                } else {
                                                    Capsule().strokeBorder(Color.hairline)
                                                }
                                            }
                                            .frame(minHeight: 44)
                                            .contentShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            TomatoPillButton(title: "Set it on the Table") {
                post()
            }
            .opacity(canPost ? 1 : 0.4)
            .disabled(!canPost)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoLoading = true
            Task {
                let raw = try? await item.loadTransferable(type: Data.self)
                // A re-pick starts a second task against the same fields —
                // only the task for the CURRENT pick may write, or a slow
                // first photo overwrites (or unlocks the post before) the
                // one actually chosen.
                guard photoItem == item else { return }
                if let raw {
                    withAnimation(.plSnap) { photoData = RecipeEditorView.processed(raw) }
                }
                photoLoading = false
            }
        }
    }

    private var photoWell: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            if let data = photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.hero))
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 5) {
                            Image(systemName: "camera")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Change")
                                .font(.jakarta(11, .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(10)
                    }
            } else {
                RoundedRectangle(cornerRadius: Radius.hero)
                    .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "camera")
                                .font(.system(size: 20, weight: .medium))
                            Text("The photo — food lives on plates")
                                .font(.jakarta(13, .bold))
                        }
                        .foregroundStyle(Color.inkFaint)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func post() {
        Haptic.plate()
        let owner = members.first(where: \.isOwner)
        let post = TablePost(
            authorName: owner?.name ?? "Me",
            authorColorHex: owner?.colorHex ?? "FF5A3C",
            dishTitle: dishTitle.trimmingCharacters(in: .whitespaces),
            caption: caption.trimmingCharacters(in: .whitespaces),
            kind: "dish",
            photoData: photoData
        )
        post.taggedNames = Array(tagged)
        context.insert(post)
        Notifier.post(
            .general, actor: owner?.name ?? "Me",
            body: "\(owner?.name ?? "Someone") set \(post.dishTitle.isEmpty ? "a dish" : post.dishTitle) on the Table.",
            into: context
        )
        dismiss()
    }
}
