import SwiftUI
import SwiftData
import PhotosUI

/// A post begins with something to share. Media and context are optional.
struct TableComposerSheet: View {
    var prefillRecipe: Recipe? = nil
    var onSaved: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    private enum Field: Hashable { case caption, title, pollChoice }
    @FocusState private var focusedField: Field?
    @State private var restored = false
    @State private var photoItem: PhotosPickerItem?
    @State private var cameraShown = false
    @State private var libraryShown = false
    @State private var photoData: Data?
    @State private var photoLoading = false
    @State private var photoLoadMessage: String?
    @State private var photoLoadID = UUID()
    @State private var dishTitle = ""
    @State private var caption = ""
    @State private var tagged: Set<String> = []
    @State private var pollOptions: [String] = []
    @State private var pollEntry = ""
    @State private var titleExpanded = false
    @State private var peopleExpanded = false
    @State private var pollExpanded = false
    @State private var discardAsked = false
    @State private var sourceAsked = false
    @State private var destinations: [TableShare.Destination] = []
    @State private var selectedDestinationID: String?
    @State private var destinationsLoaded = false
    @State private var localSaveMessage: String?
    @State private var saving = false
    @State private var draftRevision = 0
    @State private var draftSaved = false
    @State private var draftClosed = false
    @State private var draftRecoveryBlocked = false

    private var draftSnapshot: TableComposerDraft {
        TableComposerDraft(title: dishTitle, caption: caption, kind: pollExpanded ? "Question" : "Post",
            poll: pollOptions, pollEntry: pollEntry, tags: tagged.sorted(),
            destination: selectedDestinationID, photo: photoData)
    }

    private var postContent: TablePostContent {
        TablePostContent(title: dishTitle, caption: caption, hasPhoto: photoData != nil,
            choices: pollOptions, pendingChoice: pollEntry, isRecipe: prefillRecipe != nil)
    }
    private var pendingPollOption: String { pollEntry.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var postPollOptions: [String] { postContent.choices }
    private var hasContent: Bool {
        photoData != nil || !postContent.title.isEmpty || !postContent.caption.isEmpty
            || !pollOptions.isEmpty || !pendingPollOption.isEmpty || !tagged.isEmpty
    }
    private var selectedDestination: TableShare.Destination? {
        destinations.first { $0.id == selectedDestinationID }
    }
    private var canPost: Bool {
        !saving && !photoLoading && photoLoadMessage == nil && destinationsLoaded
            && (destinations.isEmpty || selectedDestination != nil) && postContent.isValid
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("New post")
                    .plType(typeSize.isAccessibilitySize ? .heading : .pageTitle,
                            typeSize.isAccessibilitySize ? .semibold : .regular)
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                IconDiscButton(systemName: "xmark", label: "Close post") {
                    focusedField = nil
                    if hasContent || photoLoading { discardAsked = true } else { dismiss() }
                }
                .alert("Keep this post for later?", isPresented: $discardAsked) {
                    Button("Save draft") { if saveDraft() { dismiss() } }
                    Button("Discard post", role: .destructive) { clearDraft(); dismiss() }
                    Button("Keep writing", role: .cancel) {}
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    authorAndAudience
                    ZStack(alignment: .topLeading) {
                        // Native vertical-field prompts truncate at accessibility
                        // sizes. Let a real multiline label establish its height.
                        if caption.isEmpty {
                            Text("What’s worth sharing?")
                                .font(.custom(Font.EditorialWeight.regular.face, size: 22, relativeTo: .body))
                                .lineSpacing(4)
                                .foregroundStyle(Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        TextField("", text: $caption, prompt: Text(""), axis: .vertical)
                            .font(.custom(Font.EditorialWeight.regular.face, size: 22, relativeTo: .body))
                            .lineSpacing(4)
                            .foregroundStyle(Color.ink)
                            .lineLimit(3...10)
                            .frame(minHeight: 140, alignment: .topLeading)
                            .focused($focusedField, equals: .caption)
                            .accessibilityLabel("Post text")
                            .accessibilityHint("Share an ingredient, a place, a meal, or a question")
                            .accessibilityIdentifier("table-post-text")
                            .plTapToFocus { focusedField = .caption }
                    }
                    if photoData != nil || photoLoading || photoLoadMessage != nil { photoPreview }
                    if titleExpanded {
                        VStack(alignment: .leading, spacing: 8) {
                            MicroLabel("Title · optional")
                            TextField("Ingredient, place, or a title", text: $dishTitle,
                                      prompt: Text("Ingredient, place, or a title").foregroundStyle(Color.inkSecondary), axis: .vertical)
                                .plType(.body)
                                .lineLimit(1...3)
                                .foregroundStyle(Color.ink)
                                .padding(14)
                                .overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline))
                                .focused($focusedField, equals: .title)
                                .accessibilityLabel("Post title, optional")
                                .accessibilityIdentifier("table-post-title")
                                .plTapToFocus { focusedField = .title }
                        }
                    }
                    if peopleExpanded { peopleEditor }
                    if pollExpanded {
                        VStack(alignment: .leading, spacing: 8) {
                            pollEditor
                            Button("Remove poll", role: .destructive) {
                                pollOptions = []; pollEntry = ""; pollExpanded = false
                            }
                            .plType(.footnote, .semibold)
                            .foregroundStyle(Color.dangerText)
                            .frame(minHeight: 44)
                            .buttonStyle(.pressable)
                        }
                    }
                    attachmentActions
                    // Keep the full privacy explanation reachable while leaving
                    // space to write when text and the keyboard are large.
                    if typeSize.isAccessibilitySize { audienceReminder }
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, 20)
            }
            .accessibilityIdentifier("table-post-scroll")
            .scrollDismissesKeyboard(.interactively)
            VStack(spacing: 8) {
                if let localSaveMessage {
                    Text(localSaveMessage)
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.dangerText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !typeSize.isAccessibilitySize { audienceReminder }
                PrimaryActionButton(title: saving ? "Saving post…" : "Post to Table", busy: saving, action: post)
                    .disabled(!canPost)
                    .accessibilityIdentifier("table-post-submit")
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .overlay(alignment: .top) { Color.hairline.frame(height: 0.5) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .interactiveDismissDisabled(hasContent || photoLoading || saving)
        .task { restoreDraft(); await loadDestinations() }
        .onChange(of: draftSnapshot) { _, _ in
            guard restored, !draftClosed else { return }
            draftSaved = false
            draftRevision += 1
        }
        .task(id: draftRevision) {
            guard restored, draftRevision > 0, !draftClosed, !draftRecoveryBlocked else { return }
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            guard !Task.isCancelled, !saving, !draftClosed, !photoLoading, photoLoadMessage == nil else { return }
            draftSaved = saveDraft(quietly: true)
        }
        .confirmationDialog("Add a photo", isPresented: $sourceAsked, titleVisibility: .visible) {
            Button("Take a photo") { cameraShown = true }
            Button("Choose from library") { chooseLibrary() }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $cameraShown) {
            CameraCapture(device: .rear) { image in
                cameraShown = false
                guard let data = image?.jpegData(compressionQuality: 0.86) else { return }
                photoLoadID = UUID(); photoLoading = false; photoLoadMessage = nil
                photoData = data
            }.ignoresSafeArea()
        }
        .photosPicker(isPresented: $libraryShown, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else {
                photoLoadID = UUID(); photoLoading = false; photoLoadMessage = nil
                return
            }
            loadPhoto(item)
        }
    }

    private var audienceReminder: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill").accessibilityHidden(true)
            Text(audiencePrivacyText)
        }
        .plType(.caption)
        .foregroundStyle(Color.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var audienceLabel: String {
        guard let destination = selectedDestination else {
            return destinations.isEmpty ? "Table unavailable · Private" : "Choose a Table"
        }
        return (destination.isOwn ? "Your Table" : destination.label) + " · Private"
    }

    private var audiencePrivacyText: String {
        guard destinationsLoaded else { return "Finding your Table…" }
        guard let destination = selectedDestination else {
            return destinations.isEmpty
                ? "Your post stays on this device until a Table is available."
                : "Choose a Table before posting."
        }
        return destination.isOwn
            ? "Only people at your Table can see this."
            : "Only people at \(destination.label) can see this."
    }

    private var authorAndAudience: some View {
        Group {
            if typeSize.isAccessibilitySize {
                stackedAuthorAndAudience
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        authorIdentity.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        draftStatus.fixedSize(horizontal: true, vertical: false)
                    }
                    stackedAuthorAndAudience
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stackedAuthorAndAudience: some View {
        VStack(alignment: .leading, spacing: 8) {
            authorIdentity
            draftStatus
        }
    }

    private var authorIdentity: some View {
        HStack(alignment: .top, spacing: 12) {
            if let me = members.me { AvatarCircle(member: me, size: 36).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 4) {
                Text(members.me?.name ?? "You")
                    .plType(.body, .semibold).foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                destinationControl
            }
        }
    }

    @ViewBuilder
    private var draftStatus: some View {
        if hasContent {
            Text(photoLoading ? "Adding photo…" : photoLoadMessage != nil || localSaveMessage != nil ? "Draft needs attention" : draftSaved ? "Draft saved" : "Saving draft…")
                .plType(.caption).foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("table-post-draft-status")
        }
    }

    @ViewBuilder
    private var destinationControl: some View {
        if !destinationsLoaded {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Finding your Table").plType(.footnote)
            }.foregroundStyle(Color.inkSecondary)
        } else if destinations.count > 1 {
            Menu {
                ForEach(destinations) { destination in
                    Button {
                        Haptic.select(); selectedDestinationID = destination.id
                    } label: {
                        if selectedDestinationID == destination.id {
                            Label(destination.label, systemImage: "checkmark")
                        } else { Text(destination.label) }
                    }
                }
            } label: {
                Label(audienceLabel, systemImage: "person.2.fill")
                    .plType(.footnote, .semibold).foregroundStyle(Color.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityLabel("Table audience")
            .accessibilityValue(selectedDestination == nil ? "Choose a Table before posting" : audienceLabel)
        } else {
            Label(audienceLabel, systemImage: "lock.fill")
                .plType(.caption).foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var attachmentActions: some View {
        VStack(alignment: .leading, spacing: 4) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                if photoData == nil && !photoLoading && photoLoadMessage == nil {
                    attachmentButton("Photo", icon: "photo") { choosePhoto() }
                }
                if !peopleExpanded && members.contains(where: { !$0.isMe }) {
                    attachmentButton("People", icon: "person.crop.circle.badge.plus") { peopleExpanded = true }
                }
                if !pollExpanded {
                    attachmentButton("Poll", icon: "chart.bar.xaxis") { pollExpanded = true }
                }
                Menu {
                    Button(titleExpanded ? "Focus title" : "Add a title", systemImage: "textformat") {
                        titleExpanded = true
                        focusedField = .title
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .plType(.footnote)
                        .foregroundStyle(Color.accentText)
                        .frame(width: typeSize.isAccessibilitySize ? nil : 44, height: 44)
                        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
                        .background(Color.raisedFill, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .accessibilityLabel("More post options")
            }

        }
        .padding(.top, 0)

    }

    private func attachmentButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .plType(.caption, .medium).foregroundStyle(Color.accentText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
                .background(Color.raisedFill, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }.buttonStyle(.pressable)
    }

    private var peopleEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel("Tag people · optional")
            ForEach(members.filter { !$0.isMe }, id: \.persistentModelID) { member in
                let active = tagged.contains(member.name)
                Button {
                    if active { tagged.remove(member.name) } else { tagged.insert(member.name) }
                } label: { // design-ok(action-wrap): full-width member selectors wrap long names at accessibility sizes.
                    HStack(spacing: 10) {
                        AvatarCircle(member: member, size: 28)
                        Text(member.name).plType(.footnote, .semibold)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(Color.fill, in: Radius.shape(Radius.chip))
                }.buttonStyle(.pressable)
                    .accessibilityLabel("Tag \(member.name)")
                    .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }

    private var photoPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let photoData, let image = UIImage(data: photoData) {
                PhotoWell(image: image, height: 225, cornerRadius: 9)
                    .accessibilityLabel("Attached photo")
                HStack(spacing: 8) {
                    attachmentButton("Change photo", icon: "photo") { choosePhoto() }
                    attachmentButton("Remove photo", icon: "xmark") { removePhoto() }
                }
            }
            if photoLoading {
                HStack(spacing: 10) { ProgressView(); Text("Getting the photo…").plType(.footnote) }
                    .foregroundStyle(Color.inkSecondary)
            }
            if let photoLoadMessage {
                Text(photoLoadMessage + " Try again, choose another, or remove it to post.")
                    .plType(.caption).foregroundStyle(Color.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
                if let photoItem {
                    attachmentButton("Retry photo", icon: "arrow.clockwise") { loadPhoto(photoItem) }
                }
            }
            if photoData == nil {
                attachmentButton("Remove photo", icon: "xmark") { removePhoto() }
            }
        }
    }

    private func choosePhoto() {
        focusedField = nil
        if UIImagePickerController.isSourceTypeAvailable(.camera) { sourceAsked = true }
        else { chooseLibrary() }
    }
    private func chooseLibrary() { photoItem = nil; libraryShown = true }
    private func removePhoto() {
        photoLoadID = UUID(); photoItem = nil; photoData = nil
        photoLoading = false; photoLoadMessage = nil
    }
    private func loadPhoto(_ item: PhotosPickerItem) {
        let request = UUID()
        photoLoadID = request; photoLoading = true; photoLoadMessage = nil
        Task {
            let raw = try? await item.loadTransferable(type: Data.self)
            guard photoLoadID == request else { return }
            if let raw, let processed = RecipeEditorView.processed(raw) { photoData = processed }
            else {
                photoLoadMessage = "That photo didn’t load."
                AccessibilityNotification.Announcement("That photo didn’t load. Try again or remove it.").post()
            }
            photoLoading = false
        }
    }

    private var pollEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel("Poll · optional")
            ForEach(pollOptions, id: \.self) { option in
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
                        withAnimation(.plSnap) { pollOptions.removeAll { $0 == option } }
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
                    TextField("Add a choice", text: $pollEntry,
                              prompt: Text("Add a choice").foregroundStyle(Color.inkSecondary))
                        .focused($focusedField, equals: .pollChoice)
                        .plType(.body, .medium)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                        .onSubmit(addPollOption)
                        .plTapToFocus { focusedField = .pollChoice }
                    Button(action: addPollOption) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.ink)
                            .frame(width: 38, height: 38)
                            .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1.5))
                            .plTapTarget()
                    }
                    .buttonStyle(.pressable)
                    .disabled(pendingPollOption.isEmpty || pollOptions.contains {
                        $0.localizedCaseInsensitiveCompare(pendingPollOption) == .orderedSame
                    })
                    .accessibilityLabel("Add poll choice")
                }
            }

            if !postPollOptions.isEmpty && postContent.caption.isEmpty {
                Text("Add a question to your post to start this poll.")
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
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

    // MARK: The one draft

    /// Save unfinished writing separately from published feed rows.
    @AppStorage("tableDraftTitle") private var draftTitle = ""
    @AppStorage("tableDraftCaption") private var draftCaption = ""
    @AppStorage("tableDraftKind") private var draftKind = "Post"
    @AppStorage("tableDraftPoll") private var draftPoll = ""
    @AppStorage("tableDraftPollEntry") private var draftPollEntry = ""
    @AppStorage("tableDraftTags") private var draftTags = ""
    @AppStorage("tableDraftDestinationOwner") private var draftDestinationOwner = ""

    private var draftKey: String {
        (PlatedApp.usesPreviewContainer ? "review-" : "")
            + (prefillRecipe.map { "recipe-" + $0.shareRecordName } ?? "table")
    }

    private func saveDraft(quietly: Bool = false) -> Bool {
        guard !photoLoading, photoLoadMessage == nil else {
            localSaveMessage = "Finish adding the photo or remove it before saving the draft."
            return false
        }
        do {
            try draftSnapshot.save(to: TableComposerDraft.url(for: draftKey))
            if !quietly { Haptic.tap() }
            return true
        } catch {
            localSaveMessage = "Couldn't save the draft. Your photo and writing are still here."
            return false
        }
    }

    private func clearDraft() {
        draftClosed = true
        if let url = try? TableComposerDraft.url(for: draftKey) { try? FileManager.default.removeItem(at: url) }
        guard prefillRecipe == nil, !PlatedApp.usesPreviewContainer else { return }
        draftTitle = ""
        draftCaption = ""
        draftKind = "Post"
        draftPoll = ""
        draftPollEntry = ""
        draftTags = ""
        draftDestinationOwner = ""
    }

    private func restoreDraft() {
        guard !restored else { return }
        restored = true
        #if DEBUG
        if PlatedApp.usesPreviewContainer {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-plated-review-post-reset"), let url = try? TableComposerDraft.url(for: draftKey) {
                try? FileManager.default.removeItem(at: url)
            }
            if args.contains("-plated-review-post-photo") { photoData = SampleData.photo("veggie") }
            if args.contains("-plated-review-post-photo-error") { photoLoadMessage = "That photo didn’t load." }
        }
        #endif
        do {
            let url = try TableComposerDraft.url(for: draftKey)
            if FileManager.default.fileExists(atPath: url.path) {
                let draft = try TableComposerDraft.load(from: url)
                dishTitle = draft.title; caption = draft.caption
                pollExpanded = draft.kind == "Question" || !draft.poll.isEmpty || !draft.pollEntry.isEmpty
                titleExpanded = !draft.title.isEmpty
                peopleExpanded = !draft.tags.isEmpty
                pollOptions = draft.poll; pollEntry = draft.pollEntry
                tagged = Set(draft.tags); selectedDestinationID = draft.destination
                photoData = draft.photo
                draftSaved = true
                return
            }
        } catch {
            draftRecoveryBlocked = true
            localSaveMessage = "The saved draft couldn't be opened. It has been kept on this device."
            return
        }
        if let prefillRecipe {
            titleExpanded = true
            dishTitle = prefillRecipe.title
            caption = prefillRecipe.summary
            photoData = prefillRecipe.photoData
            return
        }
        guard !PlatedApp.usesPreviewContainer else { return }
        dishTitle = draftTitle
        caption = draftCaption
        pollExpanded = draftKind == "Question"
        titleExpanded = !draftTitle.isEmpty
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
        peopleExpanded = !tagged.isEmpty
        selectedDestinationID = draftDestinationOwner.isEmpty ? nil : draftDestinationOwner
    }

    @MainActor
    private func loadDestinations() async {
        if PlatedApp.usesPreviewContainer {
            destinations = [TableShare.Destination(ownerID: "review-table", title: "Your Table", isOwn: true)]
            selectedDestinationID = "review-table"; destinationsLoaded = true
            return
        }
        let choices = await TableShare.writableDestinations(in: context)
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
        saving = true
        Haptic.plate()
        let content = postContent
        let publishedPollOptions = content.choices
        let owner = members.me
        let post = TablePost(
            authorName: owner?.name ?? "Me",
            authorColorHex: owner?.colorHex ?? "FF5A3C",
            dishTitle: content.title,
            caption: content.caption,
            kind: content.wireKind,
            photoData: photoData
        )
        // This happens before insertion and before the network attempt. A
        // failed save therefore remains tied to this exact Table when the feed
        // retries it, including when the choice is this account's own zone.
        if let selectedDestination {
            post.shareZoneOwner = selectedDestination.ownerID
        }
        post.taggedNames = Array(tagged)
        if !publishedPollOptions.isEmpty {
            post.pollOptions = publishedPollOptions
            post.pollCounts = Array(repeating: 0, count: publishedPollOptions.count)
        }
        context.insert(post)
        let activityIDsBefore = Set(
            context.insertedModelsArray.compactMap { model in
                (model as? PlatedNotification)?.persistentModelID
            }
        )
        if !publishedPollOptions.isEmpty {
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
                body: post.dishTitle.isEmpty ? "You posted to the Table." : "You shared \(post.dishTitle) at the Table.",
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
            saving = false
            Haptic.warn()
            AccessibilityNotification.Announcement(message).post()
            return
        }

        // A post retires its draft only after both the post and its activity
        // row are safely on disk. Closing earlier can turn a full disk into a
        // successful-looking data loss.
        localSaveMessage = nil
        clearDraft()
        onSaved()

        // Out to the table's zone, if there is one. Deliberately not awaited:
        // the post is already on screen and already saved locally, and a slow
        // upload must never hold the sheet open. A failure leaves
        // `isPublished` false, which is exactly the state the feed retries.
        if PlatedApp.usesPreviewContainer { dismiss(); return }
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
