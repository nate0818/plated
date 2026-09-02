import Foundation
import UIKit
import Vision

/// Photograph a recipe — an index card, a page torn from a magazine, your
/// grandmother's handwriting — and get text back in the order a person
/// would read it.
///
/// **Why this is not just "run Vision and join the strings."** Vision hands
/// back a bag of observations, each with a bounding box, in no particular
/// order. Concatenating them in the order they arrive scrambles a recipe
/// card into nonsense, and the importer downstream is line-oriented: it
/// decides "ingredient or step?" per line, so a bad line break is a bad
/// import no matter how good the character recognition was. Nearly all of
/// the work here is geometry — grouping observations into rows, ordering
/// each row left to right, and noticing when a wide horizontal gap means
/// two columns rather than one sentence.
///
/// Everything runs on-device. The photograph never leaves the phone.
enum RecipeScanner {

    /// Recipe words Vision's language model would otherwise "correct" into
    /// ordinary English — it has opinions about "tbsp".
    private static let vocabulary = [
        "tbsp", "tsp", "oz", "lb", "lbs", "ml", "gram", "grams", "kg",
        "preheat", "sauté", "saute", "simmer", "julienne", "deglaze",
        "Ingredients", "Instructions", "Directions", "Method", "Serves",
    ]

    /// Every image read in order, as one block of text ready for
    /// `RecipeImporter.parse`.
    static func read(_ images: [UIImage]) async -> String {
        var pages: [String] = []
        for image in images {
            if let page = await text(in: image), !page.isEmpty { pages.append(page) }
        }
        return pages.joined(separator: "\n")
    }

    /// One page. Nil when Vision could not read the image at all, which is
    /// different from reading it and finding nothing.
    static func text(in image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = cgOrientation(image.imageOrientation)

        let observations: [VNRecognizedTextObservation] = await withCheckedContinuation { continuation in
            // Off the main actor: a full-resolution accurate pass is on the
            // order of a second, and the caller is showing a spinner.
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US"]
                request.customWords = vocabulary
                let handler = VNImageRequestHandler(
                    cgImage: cgImage, orientation: orientation, options: [:]
                )
                try? handler.perform([request])
                continuation.resume(returning: request.results ?? [])
            }
        }
        guard !observations.isEmpty else { return nil }
        return lines(from: observations).joined(separator: "\n")
    }

    // MARK: Geometry

    /// One recognised fragment, in a coordinate space that reads like a page.
    ///
    /// Vision's normalized box has its origin bottom-left, so `top` is
    /// `1 - maxY`: rows sort ascending, the way you read.
    private struct Fragment {
        let text: String
        let top: CGFloat
        let height: CGFloat
        let left: CGFloat
        let right: CGFloat
    }

    private static func lines(from observations: [VNRecognizedTextObservation]) -> [String] {
        let fragments: [Fragment] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            let box = observation.boundingBox
            return Fragment(
                text: text,
                top: 1 - box.maxY,
                height: box.height,
                left: box.minX,
                right: box.maxX
            )
        }
        guard !fragments.isEmpty else { return [] }

        // Rows first. Two fragments belong to the same row when their tops
        // are within half a line height of each other — a proportion, not a
        // constant, so it survives a close-up of a card and a photo of a
        // whole page equally.
        let sorted = fragments.sorted { $0.top < $1.top }
        var rows: [[Fragment]] = []
        for fragment in sorted {
            guard var row = rows.last, let first = row.first else {
                rows.append([fragment]); continue
            }
            let tolerance = max(first.height, fragment.height) * 0.5
            if abs(fragment.top - first.top) <= tolerance {
                row.append(fragment)
                rows[rows.count - 1] = row
            } else {
                rows.append([fragment])
            }
        }

        // Then across each row, left to right — and split it where the gap
        // is too wide to be a word space.
        //
        // A card with quantities in one column and ingredients in another
        // would otherwise come back as "2 cups flour 1 tsp salt" on one
        // line, which the importer reads as a single ingredient with a very
        // strange name. A gap wider than a fifth of the page is a column
        // boundary, and a column boundary is a new line.
        var out: [String] = []
        for row in rows {
            let ordered = row.sorted { $0.left < $1.left }
            var current = ordered[0].text
            var cursor = ordered[0].right
            for fragment in ordered.dropFirst() {
                if fragment.left - cursor > 0.20 {
                    out.append(current)
                    current = fragment.text
                } else {
                    current += " " + fragment.text
                }
                cursor = fragment.right
            }
            out.append(current)
        }
        return out.map(corrected).filter { !$0.isEmpty }
    }

    /// The handful of substitutions OCR reliably gets wrong on a recipe, and
    /// nothing more. Every entry here is a character-shape confusion that
    /// changes what the importer does with the line — a mangled word in a
    /// step is cosmetic, but a mangled amount silently loses a quantity.
    private static func corrected(_ line: String) -> String {
        var s = line
        for (wrong, right) in [
            ("l/2", "1/2"), ("l/4", "1/4"), ("l/3", "1/3"), ("I/2", "1/2"),
            ("½", "1/2"), ("¼", "1/4"), ("¾", "3/4"),
            ("tbso", "tbsp"), ("tbap", "tbsp"), ("Tbsp.", "tbsp"),
            ("tsp.", "tsp"), ("0z", "oz"), ("lb.", "lb"),
        ] {
            s = s.replacingOccurrences(of: wrong, with: right)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
