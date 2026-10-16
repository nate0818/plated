import XCTest
import SwiftData
import UIKit
import WidgetKit
@testable import Plated

@MainActor
final class WidgetBridgeTests: XCTestCase {
    func testSavedHouseholdBannerReachesTheWidgetSharedContainer() throws {
        guard let shared = WidgetBridge.containerURL else {
            throw XCTSkip("The test host does not have the Plated app-group entitlement")
        }

        let names = [
            "tonight.jpg", "tonight-dark.png", "table.jpg", "cookbook.jpg",
            "household.jpg", "week-snapshot.json"
        ]
        let files = names.map { shared.appendingPathComponent($0) }
        let oldFiles = try files.map { url -> Data? in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try Data(contentsOf: url)
        }
        defer {
            for (url, oldData) in zip(files, oldFiles) {
                if let oldData {
                    try? oldData.write(to: url, options: .atomic)
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            WidgetCenter.shared.reloadAllTimelines()
        }

        let imageData = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { context in
            context.cgContext.setFillColor(UIColor.systemPink.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        }.pngData()!

        let container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        let context = container.mainContext
        context.insert(HouseholdProfile(bannerPhotoData: imageData))
        try context.save()

        WidgetBridge.publish(from: context)

        let published = try Data(contentsOf: shared.appendingPathComponent("household.jpg"))
        XCTAssertEqual(published, imageData)
        XCTAssertNotNil(UIImage(data: published), "The widget's household image must remain decodable")
    }
}
