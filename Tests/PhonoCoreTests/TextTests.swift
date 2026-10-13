import Foundation
import XCTest
@testable import PhonoCore

final class TextTests: XCTestCase {
    func testFinalize() {
        XCTAssertEqual(Transcript.finalize("  Hello there. \n", appendSpace: true), "Hello there. ")
        XCTAssertEqual(Transcript.finalize("Hello", appendSpace: false), "Hello")
        XCTAssertNil(Transcript.finalize(" \n ", appendSpace: true))
    }
}
