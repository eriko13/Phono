import Foundation

/// Swipe typing: which words a finger's path across the keys could mean.
///
/// Each word has an ideal path, through the centers of its keys in order.
/// Both paths are cut into the same number of evenly spaced points, and the
/// word whose points lie closest to the finger's wins. Common words win close
/// calls.
public enum Swipe {
    /// A word the path could mean, and how unlikely it is before looking at
    /// the path: 0 for the most likely, more for rarer words.
    public struct Candidate: Equatable, Sendable {
        public let word: String
        public let cost: Double

        public init(_ word: String, cost: Double) {
            self.word = word
            self.cost = cost
        }
    }

    /// A point on the keyboard. PhonoCore has no CoreGraphics.
    public struct Point: Equatable, Sendable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Points each path is cut into, so two paths compare point by point.
    static let samples = 32

    /// The keys under the path, in order, without one key twice in a row.
    /// `layout` maps each letter to its key's center.
    public static func keys(along path: [Point], layout: [Character: Point]) -> [Character] {
        var keys: [Character] = []
        for point in path {
            guard let key = layout.min(by: { distance($0.value, point) < distance($1.value, point) })?.key
            else { continue }
            if keys.last != key { keys.append(key) }
        }
        return keys
    }

    /// The keys whose centers are within `radius` of `point`, nearest first.
    public static func keys(near point: Point, layout: [Character: Point], within radius: Double) -> [Character] {
        layout.filter { distance($0.value, point) <= radius }
            .sorted { distance($0.value, point) < distance($1.value, point) }
            .map(\.key)
    }

    /// The words `path` most likely means, best first, at most `limit`.
    /// `keyWidth` is the width of a letter key, in the units of `layout`.
    public static func rank(
        _ candidates: [Candidate], path: [Point], layout: [Character: Point],
        keyWidth: Double, limit: Int = 4
    ) -> [String] {
        guard let start = path.first, let end = path.last, keyWidth > 0 else { return [] }
        let finger = resample(path)
        let fingerLength = length(path)
        var best: [String: Double] = [:]
        for candidate in candidates {
            guard let ideal = idealPath(candidate.word, layout),
                  // The finger starts and ends on the word's first and last
                  // keys, give or take.
                  distance(ideal[0], start) <= keyWidth * 1.1,
                  distance(ideal[ideal.count - 1], end) <= keyWidth * 1.3
            else { continue }
            let gap = zip(finger, resample(ideal)).reduce(0) { $0 + distance($1.0, $1.1) }
                / Double(samples) / keyWidth
            let stretch = abs(length(ideal) - fingerLength) / keyWidth
            let score = gap + stretch * 0.1 + candidate.cost
            if score < best[candidate.word] ?? .infinity { best[candidate.word] = score }
        }
        return best.sorted { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }
            .prefix(limit).map(\.key)
    }

    /// The centers of the word's keys. Accents are on the plain letter's key;
    /// apostrophes and hyphens are skipped. nil if a letter has no key.
    static func idealPath(_ word: String, _ layout: [Character: Point]) -> [Point]? {
        var points: [Point] = []
        for letter in word.lowercased().folding(options: .diacriticInsensitive, locale: nil) {
            if "'’-".contains(letter) { continue }
            guard let point = layout[letter] else { return nil }
            if points.last != point { points.append(point) }
        }
        return points.isEmpty ? nil : points
    }

    /// `samples` points, evenly spaced along `path`.
    static func resample(_ path: [Point]) -> [Point] {
        let total = length(path)
        guard path.count > 1, total > 0 else {
            return Array(repeating: path.first ?? Point(x: 0, y: 0), count: samples)
        }
        var points = [path[0]]
        var segment = 1
        var walked: Double = 0
        for index in 1 ..< samples - 1 {
            let target = total * Double(index) / Double(samples - 1)
            while segment < path.count - 1, walked + distance(path[segment - 1], path[segment]) < target {
                walked += distance(path[segment - 1], path[segment])
                segment += 1
            }
            let a = path[segment - 1], b = path[segment]
            let span = distance(a, b)
            let t = span > 0 ? min((target - walked) / span, 1) : 0
            points.append(Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        points.append(path[path.count - 1])
        return points
    }

    static func length(_ path: [Point]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    static func distance(_ a: Point, _ b: Point) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }
}
