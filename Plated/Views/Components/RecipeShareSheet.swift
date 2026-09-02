import SwiftUI
import SwiftData
import MessageUI

/// Where a recipe can go, named honestly.
///
/// The system share sheet on its own cannot answer the question a cook is
/// actually asking, because the two most important destinations are inside
/// Plated and iOS has never heard of them. So the app asks first — Table,
/// Discover, or out into the world — and only then hands off to iOS for the
/// part iOS is better at.
///
/// Public and private sit in separate groups with a rule between them. They
/// are one tap apart and the difference is who can read it forever, which is
/// not a difference to leave to a subtitle nobody reads.
struct RecipeShareSheet: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @State private var messagesShown = false
    @State private var activityShown = false
    @State private var confirmingDiscover = false
    @State private var copied = false
    /// The sheet's own height, measured rather than assumed.
    ///
    /// It was a literal 575, sized by hand for six rows. Two of those rows
    /// are conditional — Messages needs an account, Print needs AirPrint —
    /// so on a device without them the sheet drew the two hundred points of
    /// nothing its own comment warned about. Dynamic Type moved it too.
    /// Starts at a sensible guess so the first frame is not a jump.
    @State private var measured: CGFloat = 520

    private var owner: HouseholdMember? { members.first(where: \.isOwner) }

    /// The title block above the rows, measured the same way.
    @State private var header: CGFloat = 92

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Share")
                Text(recipe.title.isEmpty ? "This recipe" : recipe.title)
                    .plType(.title)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.top, 22)
            .padding(.bottom, 16)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { header = $0 }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    MicroLabel("On Plated")
                    OptionRow(
                        icon: "table.furniture",
                        title: "Post to your Table",
                        detail: "Your household and everyone with a seat"
                    ) {
                        RecipeShare.post(recipe, to: .table, by: owner, into: context)
                        Haptic.plate()
                        dismiss()
                    }
                    OptionRow(
                        icon: "globe",
                        title: "Share to Discover",
                        detail: "Every table on Plated can read it"
                    ) {
                        confirmingDiscover = true
                    }

                    MicroLabel("Anywhere else")
                        .padding(.top, 8)
                    // A device with no Messages account cannot send one, and
                    // the composer presents as a blank sheet rather than
                    // saying so. Same guard the scanner row uses.
                    if RecipeMessageComposer.isAvailable {
                        OptionRow(
                            icon: "message",
                            title: "Message it",
                            detail: "The photo and the whole recipe, in a text"
                        ) {
                            messagesShown = true
                        }
                    }
                    OptionRow(
                        icon: "square.and.arrow.up",
                        title: "More apps",
                        detail: "Instagram, Pinterest, X, Mail, wherever"
                    ) {
                        activityShown = true
                    }
                    if RecipePrint.isAvailable {
                        OptionRow(
                            icon: "printer",
                            title: "Print it",
                            detail: "A clean card for the fridge"
                        ) {
                            // The sheet is the thing being replaced by the
                            // print sheet, so it leaves first — two system
                            // sheets fighting for the same window is how you
                            // get a print dialog nobody can dismiss.
                            dismiss()
                            RecipePrint.present(recipe)
                        }
                    }
                    OptionRow(
                        icon: copied ? "checkmark" : "doc.on.doc",
                        title: copied ? "Copied" : "Copy the recipe",
                        detail: "Plain text, ready to paste"
                    ) {
                        UIPasteboard.general.string = RecipeShare.text(for: recipe, includeSource: false)
                        withAnimation(.plSnap) { copied = true }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                // The scroll content is the only thing here with a height
                // that is not already decided by the detent, so it is the
                // only honest thing to measure.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rows in
                    measured = header + rows
                }
            }
        }
        // Sized to the rows rather than thrown to full height: a sheet with
        // 200pt of nothing under the last option reads as a page that failed
        // to load. `.large` stays available for the type sizes that need it.
        .presentationDetents([.height(measured), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .confirmationDialog(
            "Share to Discover?",
            isPresented: $confirmingDiscover,
            titleVisibility: .visible
        ) {
            Button("Share with every table") {
                RecipeShare.post(recipe, to: .discover, by: owner, into: context)
                Haptic.plate()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anyone on Plated will be able to read this recipe and see your name on it.")
        }
        .sheet(isPresented: $messagesShown) {
            RecipeMessageComposer(recipe: recipe) { messagesShown = false }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $activityShown) {
            ShareActivityView(items: RecipeShare.activityItems(for: recipe))
                .ignoresSafeArea()
        }
    }
}

/// The recipe as a text message: the dish photo attached, the method in the
/// body, and a line about where it came from.
///
/// The photo rides as an attachment rather than trusting a link preview,
/// because the preview a link gets is whatever the far end serves — and what
/// a person wants to see when a recipe arrives is the food. Pre-written and
/// never pre-sent; the send button stays the sender's, same rule as
/// `InviteComposer`.
struct RecipeMessageComposer: UIViewControllerRepresentable {
    let recipe: Recipe
    var onFinish: () -> Void

    static var isAvailable: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.body = RecipeShare.text(for: recipe)
        if let data = recipe.photoData {
            controller.addAttachmentData(data, typeIdentifier: "public.jpeg", filename: "\(filename).jpg")
        }
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    /// Messages shows the attachment's filename to the recipient, so it says
    /// the dish rather than "image1".
    private var filename: String {
        let cleaned = recipe.title
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Recipe" : cleaned
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onFinish()
        }
    }
}

/// The system share sheet, which already contains Instagram, Pinterest, X,
/// Facebook, Mail, Notes, AirDrop and every other target the phone has, kept
/// current by the phone rather than by us.
struct ShareActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
