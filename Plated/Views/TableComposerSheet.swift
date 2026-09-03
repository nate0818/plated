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
    @State private var cameraShown = false
    @State private var libraryShown = false
    @State private var photoData: Data?
    @State private var photoLoading = false
    @State private var dishTitle = ""
    @State private var caption = ""
    @State private var tagged: Set<String> = []
    @State private var discardAsked = false
    @State private var sourceAsked = false

    /// Anything worth losing. The sheet advertises the drag-down and used to
    /// let it destroy a filled post without a word.
    private var hasContent: Bool {
        photoData != nil
            || !dishTitle.trimmingCharacters(in: .whitespaces).isEmpty
            || !caption.trimmingCharacters(in: .whitespaces).isEmpty
    }

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
                Text("What you cooked")
                    .plType(.title)
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                // 38 with a 14pt glyph, like every other header icon disc
                // in the app. This one was 32 with a 12, including against
                // the disc in the sheet it is most often opened beside.
                IconDiscButton(systemName: "xmark", label: "Close") {
                    if hasContent { discardAsked = true } else { dismiss() }
                }
                .padding(.trailing, 16)
                .padding(.top, 12)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    photoWell

                    TextField("Name the dish", text: $dishTitle)
                        .plType(.body)
                        .padding(.horizontal, 14)
                        // Floored, not fixed. Every other field in the app is
                    // floored; a hard height around type that answers
                    // Dynamic Type is the overflow CLAUDE.md already logs.
                    .frame(minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                        .plTappableField()

                    TextField("Say something about it", text: $caption, axis: .vertical)
                        .plType(.body, .medium)
                        .lineLimit(2...4)
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                        .plTappableField()

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
                                                AvatarCircle(member: member, size: 22)
                                                Text("@\(member.name)")
                                                    .plType(.micro)
                                            }
                                            .foregroundStyle(active ? Color.canvas : Color.ink)
                                            .padding(.horizontal, 10)
                                            .frame(minHeight: 36)
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
                                        .buttonStyle(.pressable)
                                        .accessibilityAddTraits(active ? .isSelected : [])
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            TomatoPillButton(title: "Post") {
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
        // A filled post doesn't die to one accidental swipe — the drag
        // rubber-bands instead. Leaving on purpose goes through the X,
        // which asks first. An empty composer still slides away freely.
        .interactiveDismissDisabled(hasContent)
        .onAppear { restoreDraft() }
        .confirmationDialog("Discard this post?", isPresented: $discardAsked, titleVisibility: .visible) {
            // A third way out. Backing out of a half-written post used to be
            // unconditionally destructive: Discard or keep sitting here.
            // `hasContent` already answers whether there is anything worth
            // keeping, which is exactly Instagram's rule for when to make
            // the offer at all. What does not transfer is a drafts shelf —
            // at one dinner a night there is only ever one draft, so it
            // restores silently the next time the composer opens.
            Button("Save draft") { saveDraft(); dismiss() }
            Button("Discard", role: .destructive) { clearDraft(); dismiss() }
            Button("Keep writing", role: .cancel) {}
        }
        .onChange(of: photoItem) { _, item in
            guard let item else {
                // Un-checking the photo inside the system picker lands here —
                // a bare return would latch photoLoading true forever (the
                // in-flight task's own guard can never clear it against nil).
                withAnimation(.plSnap) { photoData = nil }
                photoLoading = false
                return
            }
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

    /// The picture is the post, so the camera comes first.
    ///
    /// This was a bare `PhotosPicker` — the library and nothing else —
    /// wearing a camera glyph and the words "Add a photo", on the composer
    /// for an app whose whole prompt is "a photo of what you just cooked".
    /// The dish is on the counter while you are using it. Offering the roll
    /// alone means every post is something you cooked earlier.
    private var photoWell: some View {
        Button {
            Haptic.tap()
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                sourceAsked = true
            } else {
                // A simulator, or a device with no camera. One door, and it
                // is the one that works: no menu offering a thing that
                // cannot happen.
                libraryShown = true
            }
        } label: {
            if let data = photoData, let image = UIImage(data: data) {
                PhotoWell(image: image, height: 220, cornerRadius: Radius.hero)
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 5) {
                            Image(systemName: "camera")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Change")
                                .plType(.micro)
                        }
                        .foregroundStyle(Color.onScrim)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.scrim, in: Capsule())
                        .padding(10)
                    }
            } else {
                RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                    .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 150)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "camera")
                                .font(.system(size: 20, weight: .medium))
                            Text("Add a photo")
                                .plType(.footnote, .bold)
                        }
                        .foregroundStyle(Color.inkSecondary)
                    }
            }
        }
        .buttonStyle(.pressable)
        .confirmationDialog("Add a photo", isPresented: $sourceAsked, titleVisibility: .visible) {
            Button("Take a photo") { cameraShown = true }
            Button("Choose from library") { libraryShown = true }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $cameraShown) {
            CameraCapture(device: .rear) { image in
                cameraShown = false
                guard let data = image?.jpegData(compressionQuality: 0.86) else { return }
                withAnimation(.plSnap) { photoData = data }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $libraryShown, selection: $photoItem, matching: .images)
    }

    // MARK: The one draft

    /// One draft, because there is one dinner a night. Stored as plain
    /// values rather than a model row: a half-written post is not a post,
    /// and it has no business in the store the Table reads from.
    @AppStorage("tableDraftTitle") private var draftTitle = ""
    @AppStorage("tableDraftCaption") private var draftCaption = ""

    private func saveDraft() {
        draftTitle = dishTitle
        draftCaption = caption
        Haptic.tap()
    }

    private func clearDraft() {
        draftTitle = ""
        draftCaption = ""
    }

    /// The photo is deliberately not kept. A draft that restores a title and
    /// a sentence is a convenience; one that silently holds on to a
    /// photograph you chose and then walked away from is a surprise.
    private func restoreDraft() {
        guard dishTitle.isEmpty, caption.isEmpty else { return }
        dishTitle = draftTitle
        caption = draftCaption
    }

    private func post() {
        Haptic.plate()
        // Posted is the one outcome that certainly retires the draft.
        clearDraft()
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
        // Out to the table's zone, if there is one. Deliberately not awaited:
        // the post is already on screen and already saved locally, and a
        // slow upload must never hold the sheet open. A failure leaves
        // shareRecordName empty, which is exactly the state the next publish
        // attempt looks for.
        let hostName = owner?.name ?? ""
        Task { @MainActor in
            if let name = await TableShare.publish(post, hostName: hostName) {
                post.shareRecordName = name
                Persist.save(context, "publish table post")
            }
        }
        Notifier.post(
            .general, actor: owner?.name ?? "Me",
            body: "\(owner?.name ?? "Someone") posted \(post.dishTitle.isEmpty ? "a dish" : post.dishTitle) to the Table.",
            into: context
        )
        dismiss()
    }
}
