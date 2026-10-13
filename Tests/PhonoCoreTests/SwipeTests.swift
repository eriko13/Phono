import Foundation
import XCTest
@testable import PhonoCore

final class SwipeTests: XCTestCase {
    /// QWERTY, one unit per key, rows offset as on the iPhone.
    private let layout: [Character: Swipe.Point] = {
        var layout: [Character: Swipe.Point] = [:]
        for (row, (letters, offset)) in [("qwertyuiop", 0.0), ("asdfghjkl", 0.5), ("zxcvbnm", 1.5)].enumerated() {
            for (column, letter) in letters.enumerated() {
                layout[letter] = Swipe.Point(x: Double(column) + offset, y: Double(row))
            }
        }
        return layout
    }()

    /// A finger's path through the word's keys, a little off each center.
    private func path(_ word: String) -> [Swipe.Point] {
        let centers = Swipe.idealPath(word, layout)!
        var points: [Swipe.Point] = []
        for (a, b) in zip(centers, centers.dropFirst()) {
            for step in 0 ..< 8 {
                let t = Double(step) / 8
                points.append(Swipe.Point(x: a.x + (b.x - a.x) * t + 0.15, y: a.y + (b.y - a.y) * t - 0.1))
            }
        }
        points.append(Swipe.Point(x: centers.last!.x + 0.1, y: centers.last!.y + 0.1))
        return points
    }

    private func rank(_ words: [String], along word: String) -> [String] {
        Swipe.rank(words.map { Swipe.Candidate($0, cost: 0) }, path: path(word), layout: layout, keyWidth: 1)
    }

    func testTheClosestWordWins() {
        XCTAssertEqual(rank(["hollow", "help", "hello", "hell"], along: "hello").first, "hello")
        XCTAssertEqual(rank(["quite", "quiet", "quote"], along: "quiet").first, "quiet")
    }

    func testWordsStartingOrEndingElsewhereAreLeftOut() {
        XCTAssertEqual(rank(["world", "hello", "hellish"], along: "hello"), ["hello"])
    }

    func testCommonWordsWinCloseCalls() {
        let candidates = [Swipe.Candidate("tho", cost: 0.8), Swipe.Candidate("to", cost: 0)]
        XCTAssertEqual(Swipe.rank(candidates, path: path("to"), layout: layout, keyWidth: 1).first, "to")
    }

    func testAccentsAndApostrophesFollowThePlainKeys() {
        XCTAssertEqual(rank(["está", "esta"], along: "esta").count, 2)
        XCTAssertEqual(rank(["mañana"], along: "manana"), ["mañana"])
        XCTAssertEqual(rank(["don't"], along: "dont"), ["don't"])
    }

    func testKeysAlongAPath() {
        let row = [Swipe.Point(x: 0, y: 0), Swipe.Point(x: 9, y: 0)]
        XCTAssertEqual(Swipe.keys(along: Swipe.resample(row), layout: layout), Array("qwertyuiop"))
        XCTAssertEqual(Swipe.keys(near: Swipe.Point(x: 0.1, y: 0), layout: layout, within: 0.8), ["q"])
    }
}
