import Foundation
import SwiftData
import UIKit
import WidgetKit

/// Hands the week to the home screen. The app writes a small JSON snapshot
/// (plus tonight's photo) into the shared app-group container whenever the
/// scene changes; the PlatedWidgets extension reads it from the other side.
/// JSON keys are the contract — change them in both places or not at all.
enum WidgetBridge {
    static let appGroupID = "group.com.natemeadows.plated"

    struct Snapshot: Codable {
        struct Day: Codable {
            var day: String
            var planned: Bool
            var cookInitial: String
            var cookHex: String
        }
        struct Tonight: Codable {
            var title: String
            var cookInitial: String
            var cookHex: String
            var minutes: Int
            var hasPhoto: Bool
        }
        var generatedAt: Date
        var plannedCount: Int
        var tonight: Tonight?
        var days: [Day]
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Fetches the rolling week and writes the snapshot. Cheap enough to call
    /// on every scene transition; no-ops when the app group is unavailable
    /// (e.g. a build without the entitlement wired).
    @MainActor
    static func publish(from context: ModelContext) {
        guard let container = containerURL else { return }

        let today = Calendar.current.startOfDay(for: .now)
        guard let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: today) else { return }
        let predicate = #Predicate<PlannedMeal> { $0.date >= today && $0.date < weekEnd }
        let meals = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        var days: [Snapshot.Day] = []
        var tonight: Snapshot.Tonight?
        var tonightPhoto: Data?

        for offset in 0..<7 {
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: today) else { continue }
            let meal = meals.first {
                Calendar.current.isDate($0.date, inSameDayAs: date) && $0.slotValue == .dinner
            }
            days.append(Snapshot.Day(
                day: formatter.string(from: date).uppercased(),
                planned: meal != nil,
                cookInitial: meal?.cook?.firstInitial ?? "",
                cookHex: meal?.cook?.colorHex ?? ""
            ))
            if offset == 0, let meal {
                tonight = Snapshot.Tonight(
                    title: meal.title,
                    cookInitial: meal.cook?.firstInitial ?? "",
                    cookHex: meal.cook?.colorHex ?? "",
                    minutes: meal.recipe?.totalMinutes ?? 0,
                    hasPhoto: meal.recipe?.photoData != nil
                )
                tonightPhoto = meal.recipe?.photoData
            }
        }

        let snapshot = Snapshot(
            generatedAt: .now,
            plannedCount: days.filter(\.planned).count,
            tonight: tonight,
            days: days
        )

        do {
            // Photo lands first; the JSON is the commit record the widget
            // keys on, so a half-written pair can never claim a photo that
            // isn't there yet.
            let photoURL = container.appendingPathComponent("tonight.jpg")
            if let tonightPhoto, let downsized = downsize(tonightPhoto, maxSide: 400) {
                try downsized.write(to: photoURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: photoURL)
            }
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: container.appendingPathComponent("week-snapshot.json"), options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Widgets are a garnish — never let them spoil the meal.
        }
    }

    private static func downsize(_ data: Data, maxSide: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        guard scale < 1 else { return data }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.7)
    }
}
