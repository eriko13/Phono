import Foundation
import XCTest
@testable import PhonoCore

final class SettingsTests: XCTestCase {
    private var suite = ""
    private var store: UserDefaults!
    private var settings: Settings!

    override func setUpWithError() throws {
        suite = "phono.tests.\(UUID().uuidString)"
        store = try XCTUnwrap(UserDefaults(suiteName: suite))
        settings = Settings(store: store)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: suite)
    }

    func testDefaults() {
        XCTAssertEqual(settings.mode, .hold)
        XCTAssertEqual(settings.hotkey.name, "option")
        XCTAssertEqual(settings.output, .paste)
        XCTAssertTrue(settings.appendSpace)
        XCTAssertTrue(settings.sounds)
        XCTAssertEqual(settings.stopSound, "Bottle")
    }

    func testRoundTrip() {
        settings.mode = .toggle
        settings.hotkey = HotkeyPreset.named("f5")!
        settings.output = .type
        settings.stopSound = "Morse"

        XCTAssertEqual(settings.mode, .toggle)
        XCTAssertEqual(settings.hotkey.title, "F5")
        XCTAssertEqual(settings.output, .type)
        XCTAssertEqual(settings.stopSound, "Morse")
    }

    func testOldPasteSwitchStillCounts() {
        store.set(false, forKey: "autoPaste")
        XCTAssertEqual(settings.output, .copy)

        settings.output = .type
        XCTAssertEqual(settings.output, .type)
    }

    func testInvalidValuesFallBack() {
        store.set("NotASound", forKey: "stopSound")
        store.set("nonsense", forKey: "hotkey")
        store.set("nonsense", forKey: "output")

        XCTAssertEqual(settings.stopSound, "Bottle")
        XCTAssertEqual(settings.hotkey, .default)
        XCTAssertEqual(settings.output, .paste)
    }
}
