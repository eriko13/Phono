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
        XCTAssertEqual(settings.engine, .local)
        XCTAssertEqual(settings.serverURL, "")
        XCTAssertEqual(settings.serverKey, "")
    }

    func testRoundTrip() {
        settings.mode = .toggle
        settings.hotkey = HotkeyPreset.named("f5")!
        settings.output = .type
        settings.stopSound = "Morse"
        settings.engine = .server
        settings.serverURL = "http://overmn:8000"
        settings.serverKey = "secret"

        XCTAssertEqual(settings.mode, .toggle)
        XCTAssertEqual(settings.hotkey.title, "F5")
        XCTAssertEqual(settings.output, .type)
        XCTAssertEqual(settings.stopSound, "Morse")
        XCTAssertEqual(settings.engine, .server)
        XCTAssertEqual(settings.serverURL, "http://overmn:8000")
        XCTAssertEqual(settings.serverKey, "secret")
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
        store.set("nonsense", forKey: "engine")

        XCTAssertEqual(settings.stopSound, "Bottle")
        XCTAssertEqual(settings.hotkey, .default)
        XCTAssertEqual(settings.output, .paste)
        XCTAssertEqual(settings.engine, .local)
    }
}
