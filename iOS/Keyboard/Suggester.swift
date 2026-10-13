import PhonoCore
import UIKit

/// One slot in the bar above the keys.
struct Suggestion: Equatable {
    let text: String
    /// What was typed, shown in quotes. Choosing it keeps it as it is.
    var isTyped = false
    /// Space puts this in place of the typed word.
    var isCorrection = false
}

/// The suggestions of Apple's keyboard: completions and fixes for the word
/// being typed, from iOS's spell checker, and next words after a space.
@MainActor
final class Suggester {
    private let checker = UITextChecker()
    private let language = "en_US"
    private var nextWords: NextWords
    /// Text replacements from Settings › General › Keyboard, by shortcut.
    private var replacements: [String: String] = [:]
    /// Names from Contacts. They are words even if the checker does not know them.
    private var names: Set<String> = []

    /// The word pairs the user typed, in the App Group's container.
    private static let learnedFile = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: "group.io.github.eriko13.phono")?
        .appendingPathComponent("next-words.json")

    init() {
        let starter = Bundle.main.url(forResource: "next-words", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let learned = Self.learnedFile
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: [String: Int]].self, from: $0) } ?? [:]
        nextWords = NextWords(starter: starter, learned: learned)
    }

    /// The entries of the keyboard's `UILexicon`: what the user types, and
    /// the text it stands for.
    func use(_ entries: [(input: String, text: String)]) {
        for entry in entries {
            if entry.input == entry.text {
                names.insert(entry.text)
            } else {
                replacements[entry.input.lowercased()] = entry.text
            }
        }
    }

    func save() {
        guard let file = Self.learnedFile, let data = try? JSONEncoder().encode(nextWords.learned) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// Up to three, in the order the bar shows them, the best in the middle.
    func suggestions(before: String, after: String, capitalizes: Bool) -> [Suggestion] {
        // Inside a word, nothing fits.
        if let next = after.first, next.isLetter { return [] }
        let word = Typing.currentWord(before: before)
        let likely = nextWords.predictions(after: Typing.previousWord(before: before))

        guard !word.isEmpty else {
            guard before.last?.isWhitespace ?? true else { return [] }
            let words = likely.prefix(3).map { capitalizes ? $0.prefix(1).uppercased() + $0.dropFirst() : $0 }
            guard words.count == 3 else { return words.map { Suggestion(text: $0) } }
            return [words[1], words[0], words[2]].map { Suggestion(text: $0) }
        }

        // Words that often follow the last one come first.
        var candidates = completions(word)
        if isMisspelled(word) { candidates = guesses(word) + candidates }
        candidates = candidates.filter { likely.contains($0) } + candidates.filter { !likely.contains($0) }
        var seen: Set<String> = [word.lowercased()]
        candidates = candidates
            .map { Typing.matchCase($0, to: word) }
            .filter { seen.insert($0.lowercased()).inserted }

        let typed = Suggestion(text: word, isTyped: true)
        if let correction = correction(for: word) {
            let other = candidates.first { $0 != correction }
            return [typed, Suggestion(text: correction, isCorrection: true)] + (other.map { [Suggestion(text: $0)] } ?? [])
        }
        return [typed] + candidates.prefix(2).map { Suggestion(text: $0) }
    }

    /// What space should put in place of `word`, if it is a typo, a
    /// contraction without its apostrophe, or a text replacement.
    func correction(for word: String) -> String? {
        if let replacement = replacements[word.lowercased()] { return replacement }
        if let contraction = Typing.contraction(for: word) {
            let fixed = Typing.matchCase(contraction, to: word)
            return fixed == word ? nil : fixed
        }
        // Single letters, names, acronyms, and words the user kept stay.
        guard word.count > 1, !names.contains(word),
              word.dropFirst().allSatisfy({ !$0.isUppercase }),
              !UITextChecker.hasLearnedWord(word), isMisspelled(word),
              let guess = guesses(word).first,
              Typing.distance(word, guess) <= (word.count <= 3 ? 1 : 2)
        else { return nil }
        return Typing.matchCase(guess, to: word)
    }

    /// `before` is the text before `word`.
    func learn(_ word: String, before: String) {
        nextWords.learn(word, after: Typing.previousWord(before: before))
    }

    /// The user chose what they typed, so it is no longer a typo.
    func keep(_ word: String) {
        if isMisspelled(word) { UITextChecker.learnWord(word) }
    }

    private func range(_ word: String) -> NSRange {
        NSRange(location: 0, length: word.utf16.count)
    }

    private func isMisspelled(_ word: String) -> Bool {
        checker.rangeOfMisspelledWord(in: word, range: range(word), startingAt: 0, wrap: false, language: language)
            .location != NSNotFound
    }

    private func guesses(_ word: String) -> [String] {
        checker.guesses(forWordRange: range(word), in: word, language: language) ?? []
    }

    private func completions(_ word: String) -> [String] {
        checker.completions(forPartialWordRange: range(word), in: word, language: language) ?? []
    }
}
