import SwiftUI

/// The link is routed only after this sheet has left, so the join confirmation
/// never competes with the link-entry sheet for presentation.
struct HouseholdInvitationEntryView: View {
    let onOpen: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var invalid = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                Button("Cancel") { dismiss() }
                    .plType(.callout)
                    .foregroundStyle(Color.inkSecondary)
                    .plTapTarget()
                Text("Join your people.")
                    .plType(.hero)
                    .foregroundStyle(Color.ink)
                Text("Open the invitation you received, or paste its link below. You'll see what becomes shared before joining.")
                    .plType(.body)
                    .foregroundStyle(Color.inkSecondary)
                VStack(alignment: .leading, spacing: Spacing.compact) {
                    MicroLabel("Invitation link")
                    TextField("Paste your invitation link", text: $link)
                        .plType(.body)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(14)
                        .overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline))
                        .accessibilityIdentifier("household-invitation-link")
                    if invalid {
                        Text("This isn't a Plated invitation. Check the full link and try again.")
                            .plType(.footnote)
                            .foregroundStyle(Color.dangerText)
                    }
                }
                PrimaryActionButton(title: "Open invitation") {
                    guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
                          Invitation.parse(url) != nil else {
                        invalid = true
                        return
                    }
                    onOpen(url)
                    dismiss()
                }
                .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(Spacing.page)
        }
        .background(Color.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .onChange(of: link) { invalid = false }
    }
}
