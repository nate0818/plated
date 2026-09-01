import Foundation
import SwiftData
import UIKit
import WidgetKit

/// Hands the week to the home screen. The app writes a small JSON snapshot
/// (plus tonight's photo and the table's latest) into the shared app-group
/// container whenever the scene changes; the PlatedWidgets extension reads it
/// from the other side. JSON keys are the contract — change them in both
/// places or not at all.
///
/// Fields added after the first release are optional on purpose: a widget can
/// wake up holding a snapshot written by an older build, and a missing key
/// must read as "nothing to say", never as a decode failure that blanks the
/// whole widget.
enum WidgetBridge {
    static let appGroupID = "group.com.natemeadows.plated"

    struct Snapshot: Codable {
        /// Who is holding the phone, so the widget can say "You cook
        /// tonight" instead of reading the owner their own name. Optional
        /// because an older snapshot on disk won't carry it.
        var ownerName: String?
        struct Day: Codable {
            var day: String
            var planned: Bool
            var cookInitial: String
            var cookHex: String
            var cookName: String?
            var title: String?
        }
        struct Tonight: Codable {
            var title: String
            var cookInitial: String
            var cookHex: String
            var minutes: Int
            var hasPhoto: Bool
            var cookName: String?
        }
        /// What's still to buy for the rolling window the Grocery sheet shows.
        struct Grocery: Codable {
            var openCount: Int
            var totalCount: Int
            /// The first few unbought names, alphabetical, for the medium
            /// size. Never the whole list — a widget is a glance.
            var sample: [String]
        }
        /// The newest thing on the table, for the social widget.
        struct TableCard: Codable {
            var authorName: String
            var authorInitial: String
            var authorHex: String
            var dishTitle: String
            var caption: String
            var plates: Int
            var commentCount: Int
            var hasPhoto: Bool
            var postedAt: Date
        }
        var generatedAt: Date
        var plannedCount: Int
        var tonight: Tonight?
        var days: [Day]
        var grocery: Grocery?
        var table: TableCard?
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
                cookHex: meal?.cook?.colorHex ?? "",
                cookName: meal?.cook?.name,
                title: meal?.title
            ))
            if offset == 0, let meal {
                tonight = Snapshot.Tonight(
                    title: meal.title,
                    cookInitial: meal.cook?.firstInitial ?? "",
                    cookHex: meal.cook?.colorHex ?? "",
                    minutes: meal.recipe?.totalMinutes ?? 0,
                    hasPhoto: meal.recipe?.photoData != nil,
                    cookName: meal.cook?.name
                )
                tonightPhoto = meal.recipe?.photoData
            }
        }

        let grocery = groceryLine(from: context, windowStart: today)
        let (table, tablePhoto) = latestTablePost(from: context)

        let owner = (try? context.fetch(FetchDescriptor<HouseholdMember>()))?
            .first(where: \.isOwner)?.name
        let snapshot = Snapshot(
            ownerName: owner,
            generatedAt: .now,
            plannedCount: days.filter(\.planned).count,
            tonight: tonight,
            days: days,
            grocery: grocery,
            table: table
        )

        do {
            // Photos land first; the JSON is the commit record the widget
            // keys on, so a half-written set can never claim a photo that
            // isn't there yet.
            try write(photo: tonightPhoto, to: container.appendingPathComponent("tonight.jpg"))
            try write(photo: tablePhoto, to: container.appendingPathComponent("table.jpg"))
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: container.appendingPathComponent("week-snapshot.json"), options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Widgets are a garnish — never let them spoil the meal.
        }
    }

    // MARK: Pieces

    /// The same window and the same filters the Grocery sheet applies, so the
    /// number on the home screen is the number behind the basket.
    @MainActor
    private static func groceryLine(from context: ModelContext, windowStart: Date) -> Snapshot.Grocery? {
        let manualHorizon = Calendar.current.date(byAdding: .day, value: -7, to: windowStart) ?? windowStart
        let items = (try? context.fetch(
            FetchDescriptor<GroceryItem>(sortBy: [SortDescriptor(\GroceryItem.name)])
        )) ?? []
        let current = items.filter { item in
            guard !item.isDismissed else { return false }
            return item.isManual
                ? item.weekStart >= manualHorizon
                : Calendar.current.isSameDay(item.weekStart, windowStart)
        }
        guard !current.isEmpty else { return nil }
        let open = current.filter { !$0.isChecked }
        return Snapshot.Grocery(
            openCount: open.count,
            totalCount: current.count,
            sample: open.prefix(4).map(\.name)
        )
    }

    @MainActor
    private static func latestTablePost(from context: ModelContext) -> (Snapshot.TableCard?, Data?) {
        var descriptor = FetchDescriptor<TablePost>(
            predicate: #Predicate { !$0.isDiscover && $0.kind == "dish" },
            sortBy: [SortDescriptor(\TablePost.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let post = (try? context.fetch(descriptor))?.first else { return (nil, nil) }
        let card = Snapshot.TableCard(
            authorName: post.authorName,
            authorInitial: post.initials,
            authorHex: post.authorColorHex,
            dishTitle: post.dishTitle,
            caption: post.caption,
            plates: post.totalPlates,
            commentCount: post.sortedComments.count,
            hasPhoto: post.photoData != nil,
            postedAt: post.createdAt
        )
        return (card, post.photoData)
    }

    private static func write(photo: Data?, to url: URL) throws {
        if let photo, let downsized = downsize(photo, maxSide: 400) {
            try downsized.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
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
