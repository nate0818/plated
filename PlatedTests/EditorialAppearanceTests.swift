import XCTest
import SwiftUI
import UIKit
@testable import Plated

final class EditorialAppearanceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "EditorialAppearanceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        suite = nil
        super.tearDown()
    }

    func testSelectedEditorialRoomDoesNotFollowALightPhone() {
        XCTAssertEqual(Appearance.editorial.scheme, ColorScheme.dark)
        XCTAssertEqual(Appearance.editorial.uiStyle, .dark)
    }

    func testFreshInstallUsesEditorial() {
        Appearance.applyEditorialDefault(to: defaults)
        XCTAssertEqual(defaults.string(forKey: "appearance"), Appearance.editorial.rawValue)
    }

    func testPreviousAutomaticDefaultAdoptsEditorial() {
        defaults.set(Appearance.system.rawValue, forKey: "appearance")
        Appearance.applyEditorialDefault(to: defaults)
        XCTAssertEqual(defaults.string(forKey: "appearance"), Appearance.editorial.rawValue)
    }

    func testDeliberateLightChoiceIsPreserved() {
        defaults.set(Appearance.light.rawValue, forKey: "appearance")
        Appearance.applyEditorialDefault(to: defaults)
        XCTAssertEqual(defaults.string(forKey: "appearance"), Appearance.light.rawValue)
    }

    func testChoosingSystemAfterMigrationPersists() {
        Appearance.applyEditorialDefault(to: defaults)
        defaults.set(Appearance.system.rawValue, forKey: "appearance")
        Appearance.applyEditorialDefault(to: defaults)
        XCTAssertEqual(defaults.string(forKey: "appearance"), Appearance.system.rawValue)
    }

    func testInvalidOldPreferenceRecoversToEditorial() {
        defaults.set("retired-appearance", forKey: "appearance")
        Appearance.applyEditorialDefault(to: defaults)
        XCTAssertEqual(defaults.string(forKey: "appearance"), Appearance.editorial.rawValue)
    }
}
