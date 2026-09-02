import UIKit
import SwiftData
import LinkPresentation

/// Everything a recipe becomes when it leaves the cookbook.
///
/// There are three audiences and they are genuinely different places, so
/// the sheet names them rather than hiding them behind one "Share":
///
/// - **Your Table.** A `TablePost` like any other. Your household sees it,
///   and so does anyone holding a seat. Private, and it stays private.
/// - **Discover.** The same post stamped `isDiscover`, which every table on
///   Plated can read. Public. Worded as public at the point of choosing,
///   because a recipe you can't unshare is not a thing to discover after.
/// - **Off Plated entirely.** Messages, Mail, Instagram, Pinterest, X, the
///   printer. Those ride the system share sheet rather than four
///   hand-written integrations, for the reason Apple's own apps do it:
///   every one of those targets is already in there, they update
///   themselves, and a bespoke Instagram button is a thing that breaks on
///   somebody else's release schedule for no gain the cook can see.
enum RecipeShare {

    /// A shared recipe carries no link at all, deliberately.
    ///
    /// It must never carry the household's `CKShare` invitation: that link
    /// hands over a seat at your table, and texting somebody a salmon recipe
    /// is not an offer to join your family's private feed. A seat is
    /// something you give on purpose, from Seats, to a person you named.
    /// And it cannot carry a marketing URL until one exists that is ours.

    // MARK: On Plated

    enum Audience {
        /// Your household and everyone seated at your table.
        case table
        /// Every table on Plated.
        case discover

        var isDiscover: Bool { self == .discover }
    }

    /// Put the recipe on the Table as a dish post.
    ///
    /// Mirrors `TableComposerSheet.post()` rather than inventing a second
    /// shape of post: the feed, the plate count and the thread all key on
    /// `kind == "dish"`, and a recipe arriving by a different door should
    /// still be an ordinary post when it lands.
    @MainActor
    @discardableResult
    static func post(
        _ recipe: Recipe, to audience: Audience,
        by owner: HouseholdMember?, into context: ModelContext
    ) -> TablePost {
        let post = TablePost(
            authorName: owner?.name ?? "Me",
            authorColorHex: owner?.colorHex ?? "FF5A3C",
            dishTitle: recipe.title,
            caption: recipe.summary,
            kind: "dish",
            isDiscover: audience.isDiscover,
            photoData: recipe.photoData
        )
        context.insert(post)

        // Out to the table's zone, if there is one. Not awaited, for the
        // same reason the composer doesn't await it: the post is already
        // saved locally and already on screen, and a slow upload must never
        // hold a sheet open.
        let hostName = owner?.name ?? ""
        Task { @MainActor in
            if let name = await TableShare.publish(post, hostName: hostName) {
                post.shareRecordName = name
                Persist.save(context, "publish shared recipe")
            }
        }

        // Discover is not the household's business — telling everyone at
        // home that a dish went public is noise about a room they aren't in.
        if audience == .table {
            Notifier.post(
                .general, actor: owner?.name ?? "Me",
                body: "\(owner?.name ?? "Someone") put \(recipe.title.isEmpty ? "a recipe" : recipe.title) on the Table.",
                into: context
            )
        }
        return post
    }

    // MARK: Off Plated

    /// The recipe as plain text: what it is, what goes in it, what to do.
    ///
    /// Ends with a line about where it came from, because a wall of
    /// ingredients arriving in a stranger's Messages with no explanation is
    /// a wall of ingredients. `includeSource` turns that off for the
    /// clipboard, where somebody is pasting into their own notes and does
    /// not need to be sold the app they are already using.
    static func text(for recipe: Recipe, includeSource: Bool = true) -> String {
        var lines: [String] = [recipe.title.isEmpty ? "A recipe" : recipe.title]
        if !recipe.summary.isEmpty { lines.append(recipe.summary) }

        var facts: [String] = []
        if recipe.totalMinutes > 0 { facts.append(recipe.timeText) }
        facts.append("serves \(recipe.servings)")
        lines.append(facts.joined(separator: " · "))

        let ingredients = recipe.sortedIngredients
        if !ingredients.isEmpty {
            lines.append("")
            lines.append("Ingredients")
            lines.append(contentsOf: ingredients.map { "• \($0.displayText)" })
        }
        if !recipe.steps.isEmpty {
            lines.append("")
            lines.append("Method")
            lines.append(contentsOf: recipe.steps.enumerated().map { "\($0 + 1). \($1)" })
        }
        if includeSource {
            lines.append("")
            // The name, with no URL after it. This appended plated.app —
            // not ours, somebody else's parked page — to the body of every
            // recipe anyone ever shared out of this app.
            lines.append("From my cookbook on Plated.")
        }
        return lines.joined(separator: "\n")
    }

    static func image(for recipe: Recipe) -> UIImage? {
        recipe.photoData.flatMap(UIImage.init(data:))
    }

    /// What the system share sheet carries.
    ///
    /// One adapting source rather than a bag of items: a raw `UIImage` in the
    /// list makes Messages send an attachment where a link card reads better,
    /// while a bare string leaves Instagram and Pinterest with nothing to
    /// post. The source hands each destination the thing that destination can
    /// actually use.
    static func activityItems(for recipe: Recipe) -> [Any] {
        [Payload(recipe: recipe)]
    }

    final class Payload: NSObject, UIActivityItemSource {
        private let title: String
        private let body: String
        private let photo: UIImage?

        init(recipe: Recipe) {
            title = recipe.title.isEmpty ? "A recipe" : recipe.title
            body = RecipeShare.text(for: recipe)
            photo = RecipeShare.image(for: recipe)
        }

        /// The sheet builds its header from this before the real item is
        /// ready, so it has to be cheap and it has to be the right *type*.
        func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
            title
        }

        func activityViewController(
            _ controller: UIActivityViewController,
            itemForActivityType type: UIActivity.ActivityType?
        ) -> Any? {
            wantsPicture(type) ? (photo ?? body) : body
        }

        func activityViewController(
            _ controller: UIActivityViewController,
            subjectForActivityType type: UIActivity.ActivityType?
        ) -> String {
            title
        }

        /// The card at the top of the share sheet, and the preview some
        /// destinations carry through to the message they compose.
        func activityViewControllerLinkMetadata(
            _ controller: UIActivityViewController
        ) -> LPLinkMetadata? {
            let metadata = LPLinkMetadata()
            metadata.title = title
            // No URL on purpose. This pointed at plated.app, which Plated
            // does not own — it resolves to somebody else's parked page, so
            // every shared recipe carried a preview card aimed at a stranger
            // and some destinations passed that link along. A card with a
            // title and the dish's own photo is complete without it. Put a
            // URL back the day there is a page that is actually ours.
            if let photo { metadata.imageProvider = NSItemProvider(object: photo) }
            return metadata
        }

        /// Picture-first destinations. Instagram and Pinterest will not take
        /// a post that is only words, so handing them the text is the same as
        /// handing them nothing — the share appears to work and produces an
        /// empty composer. Matched on the bundle id because neither ships a
        /// `UIActivity.ActivityType` constant to compare against.
        private func wantsPicture(_ type: UIActivity.ActivityType?) -> Bool {
            guard photo != nil, let raw = type?.rawValue.lowercased() else { return false }
            if type == .saveToCameraRoll || type == .assignToContact { return true }
            return raw.contains("instagram") || raw.contains("pinterest")
        }
    }
}
