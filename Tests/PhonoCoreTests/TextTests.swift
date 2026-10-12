import Foundation
import XCTest
@testable import PhonoCore

final class TextTests: XCTestCase {
    func testFinalize() {
        XCTAssertEqual(Transcript.finalize("  Hello there. \n", appendSpace: true), "Hello there. ")
        XCTAssertEqual(Transcript.finalize("Hello", appendSpace: false), "Hello")
        XCTAssertNil(Transcript.finalize(" \n ", appendSpace: true))
    }

    func testHotwordsParse() {
        XCTAssertEqual(Hotwords.parse("Ada, Quillon\n# comment\n ada ,, Neutrino "), ["Ada", "Quillon", "Neutrino"])
        let many = (1...40).map { "w\($0)" }.joined(separator: ",")
        XCTAssertEqual(Hotwords.parse(many).count, Hotwords.limit)
    }
}
