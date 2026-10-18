import SwiftUI
import SwiftData

/// Edit a post in place while keeping its identity, comments, and reactions.
struct PostEditSheet: View {
    let post: TablePost

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @State private var dishTitle: String
    @State private var caption: String
    @State private var saving = false
    @State private var failed = false
    @State private var discardAsked = false
    @State private var measured: CGFloat = 340

    init(post: TablePost) {
        self.post = post
        _dishTitle = State(initialValue: post.dishTitle)
        _caption = State(initialValue: post.caption)
    }

    /// Nothing to save is not an error, it is a reason to be quiet.
    private var changed: Bool {
        dishTitle.trimmingCharacters(in: .whitespacesAndNewlines) != post.dishTitle
            || caption.trimmingCharacters(in: .whitespacesAndNewlines) != post.caption
    }

    private var valid: Bool {
        let title = dishTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if post.kind == "ask" { return !words.isEmpty }
        return post.photoData != nil || !title.isEmpty || !words.isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 2) {
                    MicroLabel(post.kind == "ask" ? "Your question" : "Your post")
                    Text(post.kind == "ask" ? "Edit question" : "Edit post")
                        .plType(.title)
                        .foregroundStyle(Color.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
                .padding(.bottom, 6)
                .overlay(alignment: .topTrailing) {
                    IconDiscButton(systemName: "xmark", label: "Close") {
                        if changed { discardAsked = true } else { dismiss() }
                    }
                }

                if post.kind != "ask" || !post.dishTitle.isEmpty {
                    TextField("Title · optional", text: $dishTitle)
                        .plType(.body)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline))
                        .plTappableField()
                }

                TextField(post.kind == "ask" ? "Your question" : "Say something about it", text: $caption, axis: .vertical)
                    .plType(.body, .medium)
                    .lineLimit(2...6)
                    .padding(14)
                    .overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline))
                    .plTappableField()

                if post.kind == "ask", post.hasPoll {
                    Text("Poll choices stay as posted so everyone's votes keep their meaning.")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The photograph is not editable, and saying so is kinder
                // than leaving a person hunting for the control. A photo is
                // the dinner and the dinner happened; changing it after the
                // fact would make the post a different post.
                if post.kind != "ask", post.photoData != nil {
                    Text("The photo stays as it is. Delete the post to change it.")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if failed {
                    // The write is the thing that has to succeed, so a
                    // failure says so rather than closing on a lie.
                    Text("Couldn't reach iCloud. Your post is unchanged.")
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PrimaryActionButton(title: saving ? "Saving…" : "Save changes", busy: saving) {
                    save()
                }
                .disabled(!changed || !valid || saving)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured = $0 }
        }
        .presentationDetents([.height(measured), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .interactiveDismissDisabled(changed)
        .confirmationDialog("Discard your changes?", isPresented: $discardAsked, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    /// Local first, then the wire, then close — and if the wire refuses, put
    /// the local values back rather than leaving the table disagreeing with
    /// the phone about what was said.
    private func save() {
        let newTitle = dishTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let newCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldTitle = post.dishTitle
        let oldCaption = post.caption

        saving = true
        failed = false
        post.dishTitle = newTitle
        post.caption = newCaption
        guard Persist.save(context, "edit table post") else {
            post.dishTitle = oldTitle
            post.caption = oldCaption
            saving = false
            failed = true
            return
        }

        Task {
            // A post that never published has nothing to republish, and its
            // local edit is already complete and honest. The feed retries it
            // from the current values the next time it refreshes.
            guard post.isPublished else {
                Haptic.plate()
                dismiss()
                return
            }
            let hostName = members.first(where: \.isOwner)?.name ?? ""
            if await TableShare.publish(post, hostName: hostName) != nil {
                Haptic.plate()
                dismiss()
            } else {
                post.dishTitle = oldTitle
                post.caption = oldCaption
                Persist.save(context, "edit table post rollback")
                saving = false
                failed = true
                Haptic.warn()
            }
        }
    }
}
