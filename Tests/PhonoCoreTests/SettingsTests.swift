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
        XCTAssertEqual(settings.hotkeys.map(\.name), ["option"])
        XCTAssertEqual(settings.output, .paste)
        XCTAssertTrue(settings.appendSpace)
        XCTAssertTrue(settings.sounds)
        XCTAssertEqual(settings.stopSound, "Bottle")
        XCTAssertEqual(settings.engine, .local)
        XCTAssertEqual(settings.serverURL, "")
        XCTAssertEqual(settings.serverKey, "")
        XCTAssertEqual(settings.inputDevice, "")
        XCTAssertEqual(settings.inputDeviceName, "")
    }

    func testRoundTrip() {
        settings.mode = .toggle
        settings.hotkeys = [HotkeyPreset.named("f5")!, HotkeyPreset.named("fn")!]
        settings.output = .type
        settings.stopSound = "Morse"
        settings.engine = .server
        settings.serverURL = "http://overmn:8000"
        settings.serverKey = "secret"
        settings.inputDevice = "AppleUSBAudioEngine:Shure:MV7:1"
        settings.inputDeviceName = "Shure MV7"

        XCTAssertEqual(settings.mode, .toggle)
        // Menu order, not the order they were chosen in.
        XCTAssertEqual(settings.hotkeys.map(\.name), ["fn", "f5"])
        XCTAssertEqual(settings.output, .type)
        XCTAssertEqual(settings.stopSound, "Morse")
        XCTAssertEqual(settings.engine, .server)
        XCTAssertEqual(settings.serverURL, "http://overmn:8000")
        XCTAssertEqual(settings.serverKey, "secret")
        XCTAssertEqual(settings.inputDevice, "AppleUSBAudioEngine:Shure:MV7:1")
        XCTAssertEqual(settings.inputDeviceName, "Shure MV7")
    }

    func testOldPasteSwitchStillCounts() {
        store.set(false, forKey: "autoPaste")
        XCTAssertEqual(settings.output, .copy)

        settings.output = .type
        XCTAssertEqual(settings.output, .type)
    }

    func testOldSingleShortcutStillCounts() {
        store.set("fn", forKey: "hotkey")
        XCTAssertEqual(settings.hotkeys.map(\.name), ["fn"])

        settings.hotkeys = [HotkeyPreset.named("mouse-4")!]
        XCTAssertEqual(settings.hotkeys.map(\.name), ["mouse-4"])
    }

    func testUnknownShortcutsAreDropped() {
        store.set(["nonsense", "mouse-5"], forKey: "hotkeys")
        XCTAssertEqual(settings.hotkeys.map(\.name), ["mouse-5"])

        store.set(["nonsense"], forKey: "hotkeys")
        XCTAssertEqual(settings.hotkeys, [.default])
    }

    func testInvalidValuesFallBack() {
        store.set("NotASound", forKey: "stopSound")
        store.set("nonsense", forKey: "hotkey")
        store.set("nonsense", forKey: "output")
        store.set("nonsense", forKey: "engine")

        XCTAssertEqual(settings.stopSound, "Bottle")
        XCTAssertEqual(settings.hotkeys, [.default])
        XCTAssertEqual(settings.output, .paste)
        XCTAssertEqual(settings.engine, .local)
    }
}
