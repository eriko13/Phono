import XCTest
@testable import PhonoCore

final class NextWordsTests: XCTestCase {
    private let starter = """
    : I The I'm
    *: the and to
    thank: you god
    """

    func testStarterList() {
        let words = NextWords(starter: starter)
        XCTAssertEqual(words.predictions(after: ""), ["I", "The", "I'm"])
        XCTAssertEqual(words.predictions(after: "thank"), ["you", "god", "the", "and", "to"])
        XCTAssertEqual(words.predictions(after: "zebra"), ["the", "and", "to"])
        XCTAssertEqual(words.predictions(after: nil), ["the", "and", "to"])
    }

    func testLearnedPairsComeFirst() {
        var words = NextWords(starter: starter)
        words.learn("goodness", after: "thank")
        words.learn("heavens", after: "thank")
        words.learn("heavens", after: "thank")
        XCTAssertEqual(words.predictions(after: "thank").prefix(4), ["heavens", "goodness", "you", "god"])
    }

    func testSentenceStartsAreStoredInLowercase() {
        var words = NextWords(starter: "")
        words.learn("Hello", after: "")
        words.learn("I'll", after: "")
        words.learn("Paris", after: "in")
        XCTAssertEqual(words.learned[""], ["hello": 1, "I'll": 1])
        XCTAssertEqual(words.learned["in"], ["Paris": 1])
    }

    func testNothingIsLearnedAfterOtherPunctuation() {
        var words = NextWords(starter: "")
        words.learn("then", after: nil)
        XCTAssertTrue(words.learned.isEmpty)
    }

    func testOldOneOffPairsGoPastTheLimit() {
        var words = NextWords(starter: "")
        words.learn("you", after: "thank")
        words.learn("you", after: "thank")
        for i in 0 ..< NextWords.limit {
            words.learn("w\(i)", after: "x")
        }
        XCTAssertEqual(words.learned, ["thank": ["you": 2]])
    }
}
