import Foundation
import SwiftData
import SwiftUI
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
        /// The most loved recipe, for the cookbook widget: favourites first,
        /// then the ones actually cooked most.
        struct CookbookCard: Codable {
            var title: String
            var minutes: Int
            var isFavorite: Bool
            var timesCooked: Int
            var hasPhoto: Bool
        }
        var generatedAt: Date
        var plannedCount: Int
        var tonight: Tonight?
        var days: [Day]
        var grocery: Grocery?
        var table: TableCard?
        var cookbook: CookbookCard?
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
        var tonightPhotoDark: Data?

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
                // No photograph: the widget gets the same plate the app
                // draws, not a fork-and-knife glyph. Every dish in Plated is
                // a plated disc (DishView), and the home screen was the one
                // place a dinner turned back into an icon. The plate's
                // porcelain and shadow answer the room, so it is drawn twice.
                if tonightPhoto == nil {
                    tonightPhoto = platedDish(for: meal, dark: false)
                    tonightPhotoDark = platedDish(for: meal, dark: true)
                }
            }
        }

        let grocery = groceryLine(from: context, windowStart: today)
        let (table, tablePhoto) = latestTablePost(from: context)
        let (cookbook, cookbookPhoto) = mostLovedRecipe(from: context)

        let owner = (try? context.fetch(FetchDescriptor<HouseholdMember>()))?
            .first(where: \.isOwner)?.name
        let snapshot = Snapshot(
            ownerName: owner,
            generatedAt: .now,
            plannedCount: days.filter(\.planned).count,
            tonight: tonight,
            days: days,
            grocery: grocery,
            table: table,
            cookbook: cookbook
        )

        do {
            // Photos land first; the JSON is the commit record the widget
            // keys on, so a half-written set can never claim a photo that
            // isn't there yet.
            try write(photo: tonightPhoto, to: container.appendingPathComponent("tonight.jpg"))
            try write(photo: tonightPhotoDark, to: container.appendingPathComponent("tonight-dark.png"))
            try write(photo: tablePhoto, to: container.appendingPathComponent("table.jpg"))
            try write(photo: cookbookPhoto, to: container.appendingPathComponent("cookbook.jpg"))
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
            // Ten: the large size lists that many; the medium takes four.
            sample: open.prefix(10).map(\.name)
        )
    }

    /// The recipe the cookbook widget shows: a favourite with a photograph
    /// first, then whatever has been cooked most. One with a photograph
    /// wins over a better-loved one without, because the widget is the
    /// picture; ties fall to the most recently added.
    @MainActor
    private static func mostLovedRecipe(from context: ModelContext) -> (Snapshot.CookbookCard?, Data?) {
        let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        guard !recipes.isEmpty else { return (nil, nil) }
        let ranked = recipes.sorted {
            let a = ($0.photoData != nil ? 100 : 0) + $0.loveScore
            let b = ($1.photoData != nil ? 100 : 0) + $1.loveScore
            return a != b ? a > b : $0.createdAt > $1.createdAt
        }
        guard let pick = ranked.first else { return (nil, nil) }
        let card = Snapshot.CookbookCard(
            title: pick.title,
            minutes: pick.totalMinutes,
            isFavorite: pick.isFavorite,
            timesCooked: pick.timesCooked,
            hasPhoto: pick.photoData != nil
        )
        return (card, pick.photoData)
    }

    @MainActor
    private static func latestTablePost(from context: ModelContext) -> (Snapshot.TableCard?, Data?) {
        var descriptor = FetchDescriptor<TablePost>(
            predicate: #Predicate { !$0.isDiscover && $0.kind == "dish" },
            sortBy: [SortDescriptor(\TablePost.createdAt, order: .reverse)]
        )
        // Not 1: the newest row can be a blank the mirror adopted (see
        // TablePost.isBlank), and the home screen is the last place that
        // should show an empty card. Take the newest real one.
        descriptor.fetchLimit = 8
        guard let post = (try? context.fetch(descriptor))?.first(where: \.isUserContent)
        else { return (nil, nil) }
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

    /// The app's generative plate for a night without a photograph,
    /// rasterised for the widget. Rendered above 140pt so DishView skips
    /// its Metal `drawingGroup`, which ImageRenderer cannot honour, and kept
    /// as PNG: the plate is a disc on nothing, and JPEG would fill the
    /// corners with black.
    @MainActor
    private static func platedDish(for meal: PlannedMeal, dark: Bool) -> Data? {
        let diameter: CGFloat = 200
        let plate = Group {
            if let recipe = meal.recipe {
                DishView(recipe: recipe, diameter: diameter)
            } else {
                DishView(title: meal.title, diameter: diameter)
            }
        }
        .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: plate)
        renderer.scale = 2
        renderer.isOpaque = false
        return renderer.uiImage?.pngData()
    }

    private static func write(photo: Data?, to url: URL) throws {
        // 800, not 400: the photograph fills a medium widget edge to edge
        // now, which is a thousand pixels wide on a 3x phone. A 400px
        // picture read as fog there. Decoded it is under 3MB, well inside
        // the extension's memory ceiling.
        if let photo, let downsized = downsize(photo, maxSide: 800) {
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
