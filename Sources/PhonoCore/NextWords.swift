import Foundation

/// Next-word predictions for the iPhone keyboard: a starter list of common
/// word pairs for each language, plus the pairs the user types, in any
/// language, which count first.
public struct NextWords: Sendable {
    /// By language, word, then the words that most often follow it, best
    /// first. "" is the start of a sentence, and "*" follows any word.
    private let starters: [String: [String: [String]]]
    /// How often the user typed each word after another. Kept on the phone.
    public private(set) var learned: [String: [String: Int]]

    /// The most pairs `learned` keeps. Past it, pairs typed once are dropped.
    static let limit = 5000

    /// `starters` maps a language code, such as `en`, to its list, with one
    /// line per word: `word: next next next`. The line for the start of a
    /// sentence begins with `:`, and the one for any word with `*:`.
    public init(starters: [String: String], learned: [String: [String: Int]] = [:]) {
        self.starters = starters.mapValues(Self.parse)
        self.learned = learned
    }

    private static func parse(_ text: String) -> [String: [String]] {
        var starter: [String: [String]] = [:]
        for line in text.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            starter[key] = line[line.index(after: colon)...].split(separator: " ").map(String.init)
        }
        return starter
    }

    /// Best first. `previous` is from `Typing.previousWord`; `language` picks
    /// the starter list.
    public func predictions(after previous: String?, language: String) -> [String] {
        let starter = starters[language] ?? [:]
        let key = previous ?? "*"
        let mine = (learned[key] ?? [:])
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
        let fallback = key.isEmpty ? [] : starter["*"] ?? []
        var result: [String] = []
        for word in mine + (starter[key] ?? []) + fallback where !result.contains(word) {
            result.append(word)
        }
        return result
    }

    /// Records that `word` followed `previous`.
    public mutating func learn(_ word: String, after previous: String?) {
        guard let previous, !word.isEmpty else { return }
        // Capitals at the start of a sentence are not part of the word.
        let stored = previous.isEmpty && word != "I" && !word.hasPrefix("I'") ? word.lowercased() : word
        learned[previous, default: [:]][stored, default: 0] += 1
        if learned.values.reduce(0, { $0 + $1.count }) > Self.limit {
            learned = learned.compactMapValues { pairs in
                let kept = pairs.filter { $0.value > 1 }
                return kept.isEmpty ? nil : kept
            }
        }
    }
}
