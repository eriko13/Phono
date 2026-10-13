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

final class TypingWordTests: XCTestCase {
    func testCurrentWord() {
        XCTAssertEqual(Typing.currentWord(before: "Hello wor"), "wor")
        XCTAssertEqual(Typing.currentWord(before: "I don't"), "don't")
        XCTAssertEqual(Typing.currentWord(before: "Hello "), "")
        XCTAssertEqual(Typing.currentWord(before: ""), "")
    }

    func testPreviousWord() {
        XCTAssertEqual(Typing.previousWord(before: "Thank yo"), "thank")
        XCTAssertEqual(Typing.previousWord(before: "Thank "), "thank")
        XCTAssertEqual(Typing.previousWord(before: "Done. Th"), "")
        XCTAssertEqual(Typing.previousWord(before: ""), "")
        XCTAssertNil(Typing.previousWord(before: "Well, th"))
    }

    func testMatchCase() {
        XCTAssertEqual(Typing.matchCase("hello", to: "helo"), "hello")
        XCTAssertEqual(Typing.matchCase("hello", to: "Helo"), "Hello")
        XCTAssertEqual(Typing.matchCase("hello", to: "HELO"), "HELLO")
        XCTAssertEqual(Typing.matchCase("I'm", to: "im"), "I'm")
    }

    func testContractions() {
        XCTAssertEqual(Typing.contraction(for: "dont"), "don't")
        XCTAssertEqual(Typing.contraction(for: "Im"), "I'm")
        XCTAssertNil(Typing.contraction(for: "well"))
    }

    func testDistance() {
        XCTAssertEqual(Typing.distance("teh", "the"), 1)
        XCTAssertEqual(Typing.distance("helo", "hello"), 1)
        XCTAssertEqual(Typing.distance("recieve", "receive"), 1)
        XCTAssertEqual(Typing.distance("cat", "dog"), 3)
        XCTAssertEqual(Typing.distance("", "ab"), 2)
    }
}
