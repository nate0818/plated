import Foundation

/// Turns a recipe webpage into the same review draft used by paste and scan.
///
/// Recipe sites usually publish a schema.org `Recipe` object for search
/// engines. Reading that object first is both more accurate and less invasive
/// than trying to infer a recipe from the visible page. Pages without one still
/// get a useful attempt through `RecipeImporter`, but the review says plainly
/// that the result needs a closer look.
enum RecipeURLImporter {
    enum Failure: LocalizedError {
        case invalidAddress
        case unsupportedAddress
        case couldNotReachSite
        case siteRefused(Int)
        case responseTooLarge
        case noRecipe

        var errorDescription: String? {
            switch self {
            case .invalidAddress:
                return "That web address is not valid."
            case .unsupportedAddress:
                return "Plated can import recipes from http and https links."
            case .couldNotReachSite:
                return "Couldn't open that page. Check the link and your connection."
            case .siteRefused:
                return "That site did not let Plated read the page."
            case .responseTooLarge:
                return "That page is too large to import safely."
            case .noRecipe:
                return "No recipe was found on that page."
            }
        }
    }

    private static let maximumResponseBytes = 4_000_000
    private static let maximumSourceCharacters = 24_000

    static func read(_ address: String) async throws -> ImportedRecipe {
        guard let url = normalizedURL(from: address) else { throw Failure.invalidAddress }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw Failure.unsupportedAddress
        }

        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        // A descriptive agent prevents a few recipe hosts from treating the
        // request as an anonymous scraper while remaining honest about who is
        // asking for the page.
        request.setValue("Plated Recipe Importer/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.couldNotReachSite
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Failure.siteRefused(http.statusCode)
        }
        guard data.count <= maximumResponseBytes else { throw Failure.responseTooLarge }
        guard let html = decodedHTML(data, response: response), !html.isEmpty else {
            throw Failure.noRecipe
        }

        let visible = visibleText(in: html)
        let structured = structuredRecipe(in: html)
        var draft: ImportedRecipe

        if let structured {
            // Literal page text fills optional holes such as a missing time,
            // but the site's purpose-built recipe object wins every field it
            // actually supplied.
            let fallback = await RecipeImporter.parse(visible)
            draft = RecipeImporter.reconcile(structured, with: fallback)
        } else {
            draft = await RecipeImporter.parse(visible)
            if draft.hasContent {
                draft.warnings.append(
                    "This site did not publish structured recipe details. Check the result against the original page."
                )
            }
        }

        guard draft.hasContent else { throw Failure.noRecipe }
        draft.sourceURL = url.absoluteString
        draft.sourceName = sourceName(in: html, fallback: url.host ?? "Website")
        draft.sourceText = String(visible.prefix(maximumSourceCharacters))
        draft.importMethod = "website"
        return draft.withStandardWarnings()
    }

    static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \Character.isWhitespace) else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), url.host != nil else { return nil }
        return url
    }

    // MARK: Structured recipe data

    private static func structuredRecipe(in html: String) -> ImportedRecipe? {
        let pattern = #"<script\b[^>]*type\s*=\s*[\"']application/ld\+json[^\"']*[\"'][^>]*>([\s\S]*?)</script\s*>"#
        for body in captures(pattern, in: html) {
            // Decode entities after JSON parsing, per field. Turning `&quot;`
            // into a literal quote here can make an otherwise valid JSON
            // string syntactically invalid before it reaches the decoder.
            let cleaned = body.replacingOccurrences(of: "<!--", with: "")
                .replacingOccurrences(of: "-->", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = cleaned.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data),
                  let object = findRecipeObject(in: root) else { continue }
            let parsed = recipe(from: object)
            if parsed.hasContent { return parsed }
        }
        return nil
    }

    private static func findRecipeObject(in value: Any) -> [String: Any]? {
        if let array = value as? [Any] {
            for item in array {
                if let found = findRecipeObject(in: item) { return found }
            }
            return nil
        }
        guard let object = value as? [String: Any] else { return nil }
        if typeNames(object["@type"]).contains(where: { $0.caseInsensitiveCompare("Recipe") == .orderedSame }) {
            return object
        }
        // `@graph` is the common wrapper, but some publishers nest their
        // Recipe under `mainEntity` or another arbitrary property.
        for child in object.values {
            if let found = findRecipeObject(in: child) { return found }
        }
        return nil
    }

    private static func typeNames(_ value: Any?) -> [String] {
        if let string = value as? String { return [string] }
        if let strings = value as? [String] { return strings }
        return []
    }

    private static func recipe(from object: [String: Any]) -> ImportedRecipe {
        let ingredientLines = stringArray(object["recipeIngredient"])
        let ingredients = ingredientLines
            .map(RecipeImporter.parseIngredientLine)
            .filter { !$0.name.isEmpty }
        let steps = instructionLines(object["recipeInstructions"])
            .map { stripTags($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result = ImportedRecipe(
            title: plainString(object["name"]),
            summary: plainString(object["description"]),
            servings: servingCount(object["recipeYield"]) ?? 4,
            prepMinutes: durationMinutes(object["prepTime"]),
            cookMinutes: durationMinutes(object["cookTime"]),
            ingredients: ingredients,
            steps: steps
        )
        if servingCount(object["recipeYield"]) == nil {
            result.warnings.append("The page did not say how many servings these amounts make. Plated used 4.")
        }
        return result
    }

    private static func instructionLines(_ value: Any?) -> [String] {
        guard let value else { return [] }
        if let string = value as? String {
            return string
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        if let array = value as? [Any] {
            return array.flatMap(instructionLines)
        }
        guard let object = value as? [String: Any] else { return [] }
        if let items = object["itemListElement"] { return instructionLines(items) }
        if let text = object["text"] { return instructionLines(text) }
        if let name = object["name"] as? String { return [name] }
        return []
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let strings = value as? [String] { return strings }
        if let values = value as? [Any] { return values.compactMap { $0 as? String } }
        if let string = value as? String { return [string] }
        return []
    }

    private static func plainString(_ value: Any?) -> String {
        if let string = value as? String {
            return stripTags(decodeEntities(string)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let values = value as? [Any] {
            return values.compactMap { $0 as? String }.joined(separator: ", ")
        }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func servingCount(_ value: Any?) -> Int? {
        let text = plainString(value)
        guard let match = firstMatch(#"\d+"#, in: text), let count = Int(match), count > 0 else { return nil }
        return count
    }

    private static func durationMinutes(_ value: Any?) -> Int {
        let raw = plainString(value).uppercased()
        guard !raw.isEmpty else { return 0 }
        if raw.hasPrefix("P") {
            let days = capturedInt(#"(\d+)D"#, in: raw)
            let hours = capturedInt(#"(\d+)H"#, in: raw)
            let minutes = capturedInt(#"(\d+)M"#, in: raw)
            return days * 1_440 + hours * 60 + minutes
        }
        let hours = capturedInt(#"(\d+)\s*(?:H|HR|HOUR)"#, in: raw)
        let minutes = capturedInt(#"(\d+)\s*(?:M|MIN|MINUTE)"#, in: raw)
        if hours > 0 || minutes > 0 { return hours * 60 + minutes }
        return Int(firstMatch(#"\d+"#, in: raw) ?? "") ?? 0
    }

    // MARK: Page cleanup and attribution

    private static func decodedHTML(_ data: Data, response: URLResponse) -> String? {
        if let encodingName = response.textEncodingName,
           let encoding = String.Encoding(ianaName: encodingName),
           let text = String(data: data, encoding: encoding) {
            return text
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private static func visibleText(in html: String) -> String {
        var text = html
        for element in ["script", "style", "noscript", "svg", "nav", "footer"] {
            text = replacing(#"<\#(element)\b[^>]*>[\s\S]*?</\#(element)\s*>"#, in: text, with: "\n")
        }
        text = replacing(#"<\s*(?:br|/p|/li|/h[1-6]|/div|/section|/tr)\b[^>]*>"#, in: text, with: "\n")
        text = replacing(#"<[^>]+>"#, in: text, with: " ")
        text = decodeEntities(text)

        let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
            let words = line.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
            return words.isEmpty ? nil : words
        }
        return lines.joined(separator: "\n")
    }

    private static func sourceName(in html: String, fallback: String) -> String {
        let patterns = [
            #"<meta\b[^>]*property\s*=\s*[\"']og:site_name[\"'][^>]*content\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#,
            #"<meta\b[^>]*content\s*=\s*[\"']([^\"']+)[\"'][^>]*property\s*=\s*[\"']og:site_name[\"'][^>]*>"#
        ]
        for pattern in patterns {
            if let name = captures(pattern, in: html).first {
                let cleaned = decodeEntities(name).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return fallback.replacingOccurrences(of: "www.", with: "")
    }

    private static func stripTags(_ text: String) -> String {
        decodeEntities(replacing(#"<[^>]+>"#, in: text, with: " "))
    }

    private static func decodeEntities(_ value: String) -> String {
        var text = value
        let named = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&frac12;": "1/2",
            "&frac14;": "1/4", "&frac34;": "3/4"
        ]
        for (entity, replacement) in named {
            text = text.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9a-fA-F]+);"#)
        let source = text as NSString
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: source.length)) ?? []
        for match in matches.reversed() {
            let token = source.substring(with: match.range(at: 1))
            let radix = token.lowercased().hasPrefix("x") ? 16 : 10
            let digits = radix == 16 ? String(token.dropFirst()) : token
            guard let scalar = UInt32(digits, radix: radix).flatMap(UnicodeScalar.init) else { continue }
            text = (text as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
        }
        return text
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
            return source.substring(with: match.range(at: 1))
        }
    }

    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: replacement
        )
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let source = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) else { return nil }
        return source.substring(with: match.range)
    }

    private static func capturedInt(_ pattern: String, in text: String) -> Int {
        Int(captures(pattern, in: text).first ?? "") ?? 0
    }
}

private extension String.Encoding {
    init?(ianaName: String) {
        let encoding = CFStringConvertIANACharSetNameToEncoding(ianaName as CFString)
        guard encoding != kCFStringEncodingInvalidId else { return nil }
        self = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    }
}
