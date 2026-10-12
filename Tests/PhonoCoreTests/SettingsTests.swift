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
        XCTAssertTrue(settings.autoPaste)
        XCTAssertTrue(settings.appendSpace)
        XCTAssertTrue(settings.sounds)
        XCTAssertEqual(settings.stopSound, "Bottle")
        XCTAssertEqual(settings.port, Settings.defaultPort)
        XCTAssertNil(settings.enginePath)
        XCTAssertEqual(settings.hotwords, [])
    }

    func testRoundTrip() {
        settings.mode = .toggle
        settings.hotkey = HotkeyPreset.named("f5")!
        settings.autoPaste = false
        settings.stopSound = "Morse"

        XCTAssertEqual(settings.mode, .toggle)
        XCTAssertEqual(settings.hotkey.title, "F5")
        XCTAssertFalse(settings.autoPaste)
        XCTAssertEqual(settings.stopSound, "Morse")
    }

    func testValuesWrittenWithDefaultsWrite() {
        store.set(9000, forKey: "enginePort")
        store.set("~/bin/fermion", forKey: "enginePath")
        store.set("Ada, Quillon", forKey: "hotwords")

        XCTAssertEqual(settings.port, 9000)
        XCTAssertEqual(settings.enginePath, "~/bin/fermion")
        XCTAssertEqual(settings.hotwords, ["Ada", "Quillon"])
    }

    func testInvalidValuesFallBack() {
        store.set("NotASound", forKey: "stopSound")
        store.set(80, forKey: "enginePort")
        store.set("nonsense", forKey: "hotkey")

        XCTAssertEqual(settings.stopSound, "Bottle")
        XCTAssertEqual(settings.port, Settings.defaultPort)
        XCTAssertEqual(settings.hotkey, .default)
    }
}
