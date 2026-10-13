import XCTest
@testable import PhonoCore

final class TypingTests: XCTestCase {
    func testSentencesCapitalizeAfterAnEnd() {
        XCTAssertTrue(Typing.capitalizes(after: "", .sentences))
        XCTAssertTrue(Typing.capitalizes(after: "Done. ", .sentences))
        XCTAssertTrue(Typing.capitalizes(after: "Really?  ", .sentences))
        XCTAssertTrue(Typing.capitalizes(after: "Hi\n", .sentences))
        XCTAssertFalse(Typing.capitalizes(after: "Hello ", .sentences))
        XCTAssertFalse(Typing.capitalizes(after: "Done.", .sentences))
        XCTAssertFalse(Typing.capitalizes(after: "e.g", .sentences))
    }

    func testOtherModes() {
        XCTAssertTrue(Typing.capitalizes(after: "New ", .words))
        XCTAssertFalse(Typing.capitalizes(after: "New", .words))
        XCTAssertFalse(Typing.capitalizes(after: "", .none))
        XCTAssertTrue(Typing.capitalizes(after: "ABC", .allCharacters))
    }

    func testTwoSpacesEndASentence() {
        XCTAssertTrue(Typing.spaceEndsSentence(after: "word ", lastKeyWasSpace: true))
        XCTAssertTrue(Typing.spaceEndsSentence(after: "at 5 ", lastKeyWasSpace: true))
        XCTAssertFalse(Typing.spaceEndsSentence(after: "word ", lastKeyWasSpace: false))
        XCTAssertFalse(Typing.spaceEndsSentence(after: "end. ", lastKeyWasSpace: true))
        XCTAssertFalse(Typing.spaceEndsSentence(after: " ", lastKeyWasSpace: true))
    }

    func testDictationNeedsASpaceAfterText() {
        XCTAssertTrue(Typing.needsSpace(before: "Hello"))
        XCTAssertFalse(Typing.needsSpace(before: "Hello "))
        XCTAssertFalse(Typing.needsSpace(before: ""))
    }
}
