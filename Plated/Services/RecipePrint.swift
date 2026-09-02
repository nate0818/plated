import UIKit

/// A recipe on paper.
///
/// The thing people actually print a recipe for is to stand it against the
/// kettle with wet hands, so this is not a screenshot of the app. It is a
/// card: the dish large enough to read across a counter, ingredients and
/// method in two clean columns of type, and nothing else. No app chrome, no
/// URL banner, no "printed from" footer taking up the space the method
/// wants — the one source line sits quietly at the bottom.
enum RecipePrint {

    static var isAvailable: Bool { UIPrintInteractionController.isPrintingAvailable }

    /// Raises the system print sheet. `anchor` matters on iPad, where the
    /// sheet is a popover and has to point at something; on iPhone it is
    /// ignored and the sheet comes up full width.
    static func present(_ recipe: Recipe, from anchor: UIView? = nil) {
        guard isAvailable else { return }

        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = recipe.title.isEmpty ? "Recipe" : recipe.title

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info

        let formatter = UIMarkupTextPrintFormatter(markupText: markup(for: recipe))
        // Printer margins vary; these keep the card off the edge on the
        // meanest of them without wasting a third of the page.
        formatter.perPageContentInsets = UIEdgeInsets(top: 54, left: 48, bottom: 54, right: 48)
        controller.printFormatter = formatter

        if let anchor, UIDevice.current.userInterfaceIdiom == .pad {
            controller.present(from: anchor.bounds, in: anchor, animated: true)
        } else {
            controller.present(animated: true)
        }
    }

    // MARK: The card

    private static func markup(for recipe: Recipe) -> String {
        var facts: [String] = []
        if recipe.totalMinutes > 0 { facts.append("\(recipe.totalMinutes) min") }
        facts.append("Serves \(recipe.servings)")
        if let category = recipe.categoryValue { facts.append(escape(category.rawValue)) }

        let ingredients = recipe.sortedIngredients
            .map { "<li>\(escape($0.displayText))</li>" }
            .joined()
        let steps = recipe.steps
            .map { "<li>\(escape($0))</li>" }
            .joined()

        // The dish rides along as data so the page has no network to wait
        // on: a print job that blocks on a download is a print job that
        // silently produces a blank card.
        var photo = ""
        if let data = recipe.photoData {
            photo = "<img class=\"hero\" src=\"data:image/jpeg;base64,\(data.base64EncodedString())\">"
        }

        let summary = recipe.summary.isEmpty
            ? ""
            : "<p class=\"summary\">\(escape(recipe.summary))</p>"

        return """
        <html><head><meta charset="utf-8"><style>
          body { font: 12pt/1.55 -apple-system, "Helvetica Neue", Helvetica, sans-serif; color: #1c1917; }
          h1 { font-size: 26pt; line-height: 1.1; margin: 0 0 6pt; letter-spacing: -0.02em; }
          .summary { font-size: 12pt; color: #57534e; margin: 0 0 10pt; }
          .facts { font-size: 10pt; letter-spacing: 0.08em; text-transform: uppercase;
                   color: #78716c; margin: 0 0 18pt; }
          .hero { width: 100%; max-height: 260pt; object-fit: cover; border-radius: 10pt;
                  margin: 0 0 18pt; }
          h2 { font-size: 10pt; letter-spacing: 0.1em; text-transform: uppercase;
               color: #78716c; margin: 20pt 0 8pt; border-top: 1px solid #e7e5e4; padding-top: 10pt; }
          ul, ol { margin: 0; padding-left: 16pt; }
          li { margin: 0 0 6pt; }
          /* A step split across a page break is a step you lose your place in. */
          ol li { page-break-inside: avoid; margin-bottom: 9pt; }
          footer { margin-top: 26pt; font-size: 9pt; color: #a8a29e; }
        </style></head><body>
          \(photo)
          <h1>\(escape(recipe.title.isEmpty ? "A recipe" : recipe.title))</h1>
          \(summary)
          <p class="facts">\(facts.joined(separator: " &middot; "))</p>
          \(ingredients.isEmpty ? "" : "<h2>Ingredients</h2><ul>\(ingredients)</ul>")
          \(steps.isEmpty ? "" : "<h2>Method</h2><ol>\(steps)</ol>")
          <footer>From my cookbook on Plated</footer>
        </body></html>
        """
    }

    /// Ampersands and angle brackets in a cook's own words would otherwise
    /// eat the rest of the card. "Salt & pepper" is not rare.
    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
