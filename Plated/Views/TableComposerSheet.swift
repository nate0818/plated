import SwiftUI
import SwiftData
import PhotosUI

/// Post to the Table — the photo-first composer behind the +. A plated
/// moment: the photo, the dish's name, a line about it, and whoever helped.
struct TableComposerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    private enum PostKind: String, CaseIterable, Identifiable {
        case dish = "Dish"
        case question = "Question"
        var id: String { rawValue }
    }

    @State private var kind: PostKind = .dish
    @State private var photoItem: PhotosPickerItem?
    @State private var cameraShown = false
    @State private var libraryShown = false
    @State private var photoData: Data?
    @State private var photoLoading = false
    @State private var photoLoadMessage: String?
    @State private var dishTitle = ""
    @State private var caption = ""
    @State private var tagged: Set<String> = []
    @State private var pollOptions: [String] = []
    @State private var pollEntry = ""
    @State private var discardAsked = false
    @State private var sourceAsked = false
    @State private var destinations: [TableShare.Destination] = []
    @State private var selectedDestinationID: String?
    @State private var destinationsLoaded = false
    @State private var localSaveMessage: String?

    /// Anything worth losing. The sheet advertises the drag-down and used to
    /// let it destroy a filled post without a word.
    private var hasContent: Bool {
        photoData != nil
            || !dishTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pollOptions.isEmpty
            || !pendingPollOption.isEmpty
            || !tagged.isEmpty
    }

    /// The choice in the field is already part of the person's draft even if
    /// they never tap +. Posting and validation use this same finalized list so
    /// the field can never look filled and then be silently dropped.
    private var pendingPollOption: String {
        pollEntry.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var postPollOptions: [String] {
        var choices = pollOptions
        guard !pendingPollOption.isEmpty,
              choices.count < 4,
              !choices.contains(where: {
                  $0.localizedCaseInsensitiveCompare(pendingPollOption) == .orderedSame
              })
        else { return choices }
        choices.append(pendingPollOption)
        return choices
    }

    private var selectedDestination: TableShare.Destination? {
        guard let selectedDestinationID else { return nil }
        return destinations.first { $0.id == selectedDestinationID }
    }

    private var destinationReady: Bool {
        destinationsLoaded && (destinations.isEmpty || selectedDestination != nil)
    }

    /// A picked photo that is still resolving holds the post — a fast tap
    /// on the pill must never silently ship without it.
    private var canPost: Bool {
        guard !photoLoading, destinationReady else { return false }
        switch kind {
        case .dish:
            return photoData != nil || !dishTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .question:
            return !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && postPollOptions.count != 1
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Private · invite only")
                Text("Share at the Table")
                    .plType(.title)
                    .foregroundStyle(Color.ink)
                Text("A dish worth remembering or a question for your people.")
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 56)
                    .padding(.top, 3)
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
                    Picker("What are you sharing?", selection: $kind) {
                        ForEach(PostKind.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Choose a dish post or a question")

                    postFields

                    if members.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            MicroLabel(kind == .dish ? "Who helped · optional" : "Ask someone · optional")
                            // A big table overflows a plain row — the chips
                            // scroll sideways instead of walking off-screen.
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(members.filter { !$0.isMe }, id: \.persistentModelID) { member in
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
                                                    .plActionLabel()
                                            }
                                            .foregroundStyle(active ? Color.canvas : Color.ink)
                                            .padding(.horizontal, 10)
                                            .frame(minHeight: 36)
                                            .background {
                                                if active {
                                                    Capsule().fill(Color.ink)
                                                } else {
                                                    Radius.shape(Radius.chip).strokeBorder(Color.hairline)
                                                }
                                            }
                                            .frame(minHeight: 44)
                                            .contentShape(Radius.shape(Radius.chip))
                                        }
                                        .buttonStyle(.pressable)
                                        .accessibilityAddTraits(active ? .isSelected : [])
                                    }
                                }
                            }
                        }
                    }

                    destinationControl

                    Label("Only people at your Table can see this.", systemImage: "lock.fill")
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            VStack(spacing: 10) {
                if let localSaveMessage {
                    Text(localSaveMessage)
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.dangerText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PrimaryActionButton(title: primaryTitle) {
                    post()
                }
                .disabled(!canPost)
            }
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
        .onAppear {
            restoreDraft()
            Task { await loadDestinations() }
        }
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
                photoLoadMessage = nil
                return
            }
            loadPhoto(item)
        }
    }

    private var primaryTitle: String {
        if localSaveMessage != nil { return "Try saving again" }
        switch kind {
        case .dish: return "Share dish"
        case .question: return postPollOptions.isEmpty ? "Ask the Table" : "Ask with poll"
        }
    }

    @ViewBuilder
    private var destinationControl: some View {
        if !destinationsLoaded {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.inkSecondary)
                Text("Finding your Table")
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(minHeight: 44)
        } else if destinations.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Share with")
                Menu {
                    ForEach(destinations) { destination in
                        Button {
                            Haptic.select()
                            selectedDestinationID = destination.id
                        } label: {
                            if selectedDestinationID == destination.id {
                                Label(destination.label, systemImage: "checkmark")
                            } else {
                                Text(destination.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.inkSecondary)
                        Text(selectedDestination?.label ?? "Choose a Table")
                            .plType(.body, .medium)
                            .foregroundStyle(selectedDestination == nil ? Color.inkSecondary : Color.ink)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "table.furniture")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.inkFaint)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .strokeBorder(Color.hairline)
                    }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Table audience")
                .accessibilityValue(selectedDestination?.label ?? "Not chosen")

                if selectedDestination == nil {
                    Text("Choose which private Table sees this post.")
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var postFields: some View {
        switch kind {
        case .dish:
            photoWell

            if let photoLoadMessage {
                HStack(spacing: 10) {
                    Text(photoLoadMessage)
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Try again") {
                        guard let photoItem else { return }
                        loadPhoto(photoItem)
                    }
                    .plType(.footnote, .bold)
                    .plActionLabel()
                    .foregroundStyle(Color.accentText)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.pressable)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Dish")
                TextField("Name the dish", text: $dishTitle)
                    .plType(.body)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .plTappableField()
            }

            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("The story · optional")
                TextField("What made it good?", text: $caption, axis: .vertical)
                    .plType(.body, .medium)
                    .lineLimit(2...4)
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .plTappableField()
            }

        case .question:
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Your question")
                TextField("What do you want to ask?", text: $caption, axis: .vertical)
                    .plType(.body, .medium)
                    .lineLimit(2...5)
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .plTappableField()
            }

            pollEditor
        }
    }

    private var pollEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel("Poll · optional")
            ForEach(Array(pollOptions.enumerated()), id: \.offset) { index, option in
                HStack(spacing: 10) {
                    Image(systemName: "circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.inkFaint)
                    Text(option)
                        .plType(.body)
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Button {
                        Haptic.tap()
                        withAnimation(.plSnap) { _ = pollOptions.remove(at: index) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.inkSecondary)
                            .plTapTarget()
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Remove \(option)")
                }
                .padding(.leading, 12)
                .frame(minHeight: 44)
                .background(Color.fill, in: Radius.shape(Radius.chip))
            }

            if pollOptions.count < 4 {
                HStack(spacing: 8) {
                    TextField("Add a choice", text: $pollEntry)
                        .plType(.body, .medium)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                        .onSubmit(addPollOption)
                        .plTappableField()
                    Button(action: addPollOption) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.ink)
                            .frame(width: 38, height: 38)
                            .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1.5))
                            .plTapTarget()
                    }
                    .buttonStyle(.pressable)
                    .disabled(pollEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add poll choice")
                }
            }

            if postPollOptions.count == 1 {
                Text("Add one more choice to post a poll.")
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }

    private func addPollOption() {
        let option = pollEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !option.isEmpty, pollOptions.count < 4,
              !pollOptions.contains(where: { $0.localizedCaseInsensitiveCompare(option) == .orderedSame })
        else { return }
        Haptic.tap()
        withAnimation(.plSnap) { pollOptions.append(option) }
        pollEntry = ""
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        photoLoading = true
        photoLoadMessage = nil
        Task {
            let raw = try? await item.loadTransferable(type: Data.self)
            // A re-pick starts a second task against the same fields — only
            // the task for the CURRENT pick may write, or a slow first photo
            // overwrites (or unlocks the post before) the one actually chosen.
            guard photoItem == item else { return }
            if let raw, let processed = RecipeEditorView.processed(raw) {
                withAnimation(.plSnap) { photoData = processed }
            } else {
                photoLoadMessage = "That photo didn’t load."
                AccessibilityNotification.Announcement(
                    "That photo didn’t load. Try again or choose another photo."
                ).post()
            }
            photoLoading = false
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
                                .plActionLabel()
                        }
                        .foregroundStyle(Color.onScrim)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.scrim, in: Radius.shape(Radius.chip))
                        .padding(10)
                    }
            } else {
                RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                    .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 150)
                    .overlay {
                        // Two states hid behind one dimmed Post button:
                        // nothing chosen yet, which the dashed well below
                        // explains perfectly well, and a photo chosen and
                        // still resolving, where the well was empty and the
                        // block had no visible cause at all. A disabled
                        // primary only works when the unmet requirement is
                        // visible on the same screen.
                        if photoLoading {
                            VStack(spacing: 8) {
                                ProgressView().tint(Color.inkSecondary)
                                Text("Getting the photo")
                                    .plType(.footnote, .bold)
                            }
                            .foregroundStyle(Color.inkSecondary)
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "camera")
                                    .font(.system(size: 20, weight: .medium))
                                Text("Add a photo · optional")
                                    .plType(.footnote, .bold)
                            }
                            .foregroundStyle(Color.inkSecondary)
                        }
                    }
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(photoData == nil ? "Add an optional photo" : "Change photo")
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
    @AppStorage("tableDraftKind") private var draftKind = PostKind.dish.rawValue
    @AppStorage("tableDraftPoll") private var draftPoll = ""
    @AppStorage("tableDraftPollEntry") private var draftPollEntry = ""
    @AppStorage("tableDraftTags") private var draftTags = ""
    @AppStorage("tableDraftDestinationOwner") private var draftDestinationOwner = ""

    private func saveDraft() {
        draftTitle = dishTitle
        draftCaption = caption
        draftKind = kind.rawValue
        draftPoll = pollOptions.joined(separator: "\n")
        draftPollEntry = pollEntry
        draftTags = tagged.sorted().joined(separator: "\n")
        draftDestinationOwner = selectedDestinationID ?? ""
        Haptic.tap()
    }

    private func clearDraft() {
        draftTitle = ""
        draftCaption = ""
        draftKind = PostKind.dish.rawValue
        draftPoll = ""
        draftPollEntry = ""
        draftTags = ""
        draftDestinationOwner = ""
    }

    /// The photo is deliberately not kept. A draft that restores a title and
    /// a sentence is a convenience; one that silently holds on to a
    /// photograph you chose and then walked away from is a surprise.
    private func restoreDraft() {
        guard dishTitle.isEmpty, caption.isEmpty else { return }
        dishTitle = draftTitle
        caption = draftCaption
        kind = PostKind(rawValue: draftKind) ?? .dish
        let savedChoices = draftPoll
            .components(separatedBy: CharacterSet.newlines)
            .filter { !$0.isEmpty }
        pollOptions = Array(savedChoices.prefix(4))
        pollEntry = draftPollEntry
        let availableNames = Set(members.filter { !$0.isMe }.map(\.name))
        tagged = Set(
            draftTags
                .components(separatedBy: CharacterSet.newlines)
                .filter { !$0.isEmpty && availableNames.contains($0) }
        )
        selectedDestinationID = draftDestinationOwner.isEmpty ? nil : draftDestinationOwner
    }

    @MainActor
    private func loadDestinations() async {
        let choices = await TableShare.writableDestinations()
        let preferred = selectedDestinationID
        destinations = choices
        switch choices.count {
        case 0:
            selectedDestinationID = nil
        case 1:
            selectedDestinationID = choices[0].id
        default:
            selectedDestinationID = preferred.flatMap { wanted in
                choices.contains(where: { $0.id == wanted }) ? wanted : nil
            }
        }
        destinationsLoaded = true
    }

    private func post() {
        guard canPost else { return }
        Haptic.plate()
        let publishedPollOptions = kind == .question ? postPollOptions : []
        let owner = members.me
        let post = TablePost(
            authorName: owner?.name ?? "Me",
            authorColorHex: owner?.colorHex ?? "FF5A3C",
            dishTitle: kind == .dish ? dishTitle.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind == .dish ? "dish" : "ask",
            photoData: kind == .dish ? photoData : nil
        )
        // This happens before insertion and before the network attempt. A
        // failed save therefore remains tied to this exact Table when the feed
        // retries it, including when the choice is this account's own zone.
        if let selectedDestination {
            post.shareZoneOwner = selectedDestination.ownerID
        }
        post.taggedNames = Array(tagged)
        if kind == .question {
            post.pollOptions = publishedPollOptions
            post.pollCounts = Array(repeating: 0, count: publishedPollOptions.count)
        }
        context.insert(post)
        let activityIDsBefore = Set(
            context.insertedModelsArray.compactMap { model in
                (model as? PlatedNotification)?.persistentModelID
            }
        )
        if kind == .question {
            Notifier.post(
                .askPosted, actor: owner?.name ?? "Me",
                body: publishedPollOptions.isEmpty
                    ? "You asked the Table a question."
                    : "You asked the Table and added a poll.",
                into: context
            )
        } else {
            Notifier.post(
                .general, actor: owner?.name ?? "Me",
                body: "You posted \(post.dishTitle.isEmpty ? "a dish" : post.dishTitle) to the Table.",
                into: context
            )
        }
        let newActivity = context.insertedModelsArray
            .compactMap { $0 as? PlatedNotification }
            .first { !activityIDsBefore.contains($0.persistentModelID) }
        // The local post and its local activity row are durable before either
        // the sheet closes or a CloudKit task gets a chance to suspend. An
        // offline post must survive termination so the feed can retry it.
        guard Persist.save(context, "new table post") else {
            // A failed transaction leaves inserted models live in this shared
            // context. Remove only the two this attempt made so tapping retry
            // cannot later save a duplicate; the visible draft stays intact.
            context.delete(post)
            if let newActivity { context.delete(newActivity) }
            let message = "Couldn't save this post yet. Your draft is still here."
            localSaveMessage = message
            Haptic.warn()
            AccessibilityNotification.Announcement(message).post()
            return
        }

        // A post retires its draft only after both the post and its activity
        // row are safely on disk. Closing earlier can turn a full disk into a
        // successful-looking data loss.
        localSaveMessage = nil
        clearDraft()

        // Out to the table's zone, if there is one. Deliberately not awaited:
        // the post is already on screen and already saved locally, and a slow
        // upload must never hold the sheet open. A failure leaves
        // `isPublished` false, which is exactly the state the feed retries.
        let hostName = owner?.name ?? ""
        // They just spoke to the table. Hearing back is the next wish, and
        // this is one of the three moments that may spend the ask. Now, not
        // after the upload: the upload may never finish.
        Task { await NotificationScheduler.askOnce() }
        Task { @MainActor in
            if let name = await TableShare.publish(post, hostName: hostName) {
                post.shareRecordName = name
                post.isPublished = true
                Persist.save(context, "publish table post")
            }
        }
        dismiss()
    }
}
