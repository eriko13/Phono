import Foundation
import XCTest
@testable import PhonoCore

final class ModifierTriggerTests: XCTestCase {
    let option = ModifierFlags.option
    let leftOptionCode: UInt16 = 58
    let rightOptionCode: UInt16 = 61
    let fnCode: UInt16 = 63
    let commandCode: UInt16 = 55

    func testCleanPressAndRelease() {
        var state = ModifierTriggerState(key: .option)
        XCTAssertEqual(state.flagsChanged(keyCode: leftOptionCode, flags: option), .pressed)
        XCTAssertEqual(state.flagsChanged(keyCode: leftOptionCode, flags: 0), .released)
    }

    func testKeyWhileHeldInterruptsAndSwallowsRelease() {
        var state = ModifierTriggerState(key: .option)
        XCTAssertEqual(state.flagsChanged(keyCode: leftOptionCode, flags: option), .pressed)
        XCTAssertEqual(state.otherInput(), .interrupted)      // ⌥←
        XCTAssertNil(state.otherInput())                       // only once
        XCTAssertNil(state.flagsChanged(keyCode: leftOptionCode, flags: 0))
        // The next clean press works again.
        XCTAssertEqual(state.flagsChanged(keyCode: leftOptionCode, flags: option), .pressed)
    }

    func testOtherModifierWhileHeldInterrupts() {
        var state = ModifierTriggerState(key: .option)
        _ = state.flagsChanged(keyCode: leftOptionCode, flags: option)
        XCTAssertEqual(state.flagsChanged(keyCode: commandCode, flags: option | ModifierFlags.command), .interrupted)
        XCTAssertNil(state.flagsChanged(keyCode: commandCode, flags: option))
        XCTAssertNil(state.flagsChanged(keyCode: leftOptionCode, flags: 0))
    }

    func testPressDuringChordNeverStarts() {
        var state = ModifierTriggerState(key: .option)
        XCTAssertNil(state.flagsChanged(keyCode: leftOptionCode, flags: option | ModifierFlags.command))
        XCTAssertNil(state.flagsChanged(keyCode: leftOptionCode, flags: ModifierFlags.command))
    }

    func testOtherInputIgnoredWhenNotHeld() {
        var state = ModifierTriggerState(key: .option)
        XCTAssertNil(state.otherInput())
    }

    func testRightOptionIgnoresLeft() {
        var state = ModifierTriggerState(key: .rightOption)
        XCTAssertNil(state.flagsChanged(keyCode: leftOptionCode, flags: option | 0x20))
        XCTAssertNil(state.flagsChanged(keyCode: leftOptionCode, flags: 0))
        XCTAssertEqual(state.flagsChanged(keyCode: rightOptionCode, flags: option | ModifierFlags.rightOptionDevice), .pressed)
        XCTAssertEqual(state.flagsChanged(keyCode: rightOptionCode, flags: 0), .released)
    }

    func testFn() {
        var state = ModifierTriggerState(key: .fn)
        XCTAssertEqual(state.flagsChanged(keyCode: fnCode, flags: ModifierFlags.function), .pressed)
        XCTAssertEqual(state.otherInput(), .interrupted)       // fn-F5, fn-arrow
        XCTAssertNil(state.flagsChanged(keyCode: fnCode, flags: 0))
        XCTAssertEqual(state.flagsChanged(keyCode: fnCode, flags: ModifierFlags.function), .pressed)
        XCTAssertEqual(state.flagsChanged(keyCode: fnCode, flags: 0), .released)
    }

    func testBothOptionKeysCountAsOneHold() {
        var state = ModifierTriggerState(key: .option)
        XCTAssertEqual(state.flagsChanged(keyCode: leftOptionCode, flags: option), .pressed)
        XCTAssertNil(state.flagsChanged(keyCode: rightOptionCode, flags: option))
        XCTAssertNil(state.flagsChanged(keyCode: leftOptionCode, flags: option))
        XCTAssertEqual(state.flagsChanged(keyCode: rightOptionCode, flags: 0), .released)
    }
}

final class HotkeyPresetTests: XCTestCase {
    func testNamesAreUnique() {
        XCTAssertEqual(Set(HotkeyPreset.all.map(\.name)).count, HotkeyPreset.all.count)
    }

    func testDefaultIsOption() {
        XCTAssertEqual(HotkeyPreset.default.trigger, .modifier(.option))
        XCTAssertTrue(HotkeyPreset.default.isModifierOnly)
        XCTAssertFalse(HotkeyPreset.named("f5")!.isModifierOnly)
    }
}
