/// Rules of Apple's keyboard that the iPhone keyboard follows. Text in,
/// answers out, so they test on any platform.
public enum Typing {
    /// What the text field asks for, as `UITextAutocapitalizationType`.
    public enum Capitalization: Sendable {
        case none, words, sentences, allCharacters
    }

    /// Whether the next letter typed after `before` is a capital.
    public static func capitalizes(after before: String, _ mode: Capitalization) -> Bool {
        // In Spanish, ¿ and ¡ open a question or exclamation; the letter after
        // one is capital where the sentence or word starts.
        if let last = before.last, opensSentence(last), mode != .allCharacters {
            return capitalizes(after: String(before.dropLast()), mode)
        }
        switch mode {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            return before.last.map(\.isWhitespace) ?? true
        case .sentences:
            guard let last = before.last else { return true }
            if last.isNewline { return true }
            guard last == " " else { return false }
            guard let end = before.last(where: { $0 != " " }) else { return true }
            return endsSentence(end)
        }
    }

    /// Two spaces after a word end the sentence: whether the second space,
    /// typed after `before`, becomes ". ".
    public static func spaceEndsSentence(after before: String, lastKeyWasSpace: Bool) -> Bool {
        lastKeyWasSpace && before.hasSuffix(" ")
            && before.dropLast().last.map { $0.isLetter || $0.isNumber } == true
    }

    /// The word the cursor is at the end of, or "".
    public static func currentWord(before: String) -> String {
        String(before.reversed().prefix(while: isWordCharacter).reversed())
    }

    /// The word before the one at the cursor, lowercased, for next-word
    /// predictions. "" at the start of a sentence; nil after other
    /// punctuation, such as a comma.
    public static func previousWord(before: String) -> String? {
        let text = before.dropLast(currentWord(before: before).count)
        let trimmed = text.reversed().drop { $0 == " " }
        guard let last = trimmed.first else { return "" }
        if endsSentence(last) || opensSentence(last) { return "" }
        guard isWordCharacter(last) else { return nil }
        return String(trimmed.prefix(while: isWordCharacter).reversed()).lowercased()
    }

    /// Gives `suggestion` the case of what was typed: a capital first letter,
    /// or all capitals.
    public static func matchCase(_ suggestion: String, to typed: String) -> String {
        guard let first = typed.first, first.isUppercase else { return suggestion }
        if typed.count > 1, typed.allSatisfy({ !$0.isLetter || $0.isUppercase }) {
            return suggestion.uppercased()
        }
        return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
    }

    /// Common words typed without their apostrophe. A spell checker does not
    /// always offer these.
    public static func contraction(for word: String) -> String? {
        contractions[word.lowercased()]
    }

    private static let contractions = [
        "i": "I", "im": "I'm", "ive": "I've",
        "dont": "don't", "doesnt": "doesn't", "didnt": "didn't", "cant": "can't",
        "wont": "won't", "isnt": "isn't", "arent": "aren't", "wasnt": "wasn't",
        "werent": "weren't", "couldnt": "couldn't", "wouldnt": "wouldn't",
        "shouldnt": "shouldn't", "havent": "haven't", "hasnt": "hasn't",
        "youre": "you're", "youve": "you've", "theyre": "they're", "theyve": "they've",
        "thats": "that's", "whats": "what's", "theres": "there's", "heres": "here's",
    ]

    /// Letters a word needs to change to become `other`: an insertion, a
    /// deletion, a substitution, or a swap of two neighbors each count one.
    public static func distance(_ word: String, _ other: String) -> Int {
        let a = Array(word.lowercased()), b = Array(other.lowercased())
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0 ... a.count { table[i][0] = i }
        for j in 0 ... b.count { table[0][j] = j }
        for i in 1 ... a.count {
            for j in 1 ... b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, table[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1)
                }
            }
        }
        return table[a.count][b.count]
    }

    private static func endsSentence(_ c: Character) -> Bool {
        ".!?".contains(c) || c.isNewline
    }

    private static func opensSentence(_ c: Character) -> Bool {
        c == "¿" || c == "¡"
    }

    private static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c == "'" || c == "’"
    }

    /// Dictated text goes after a space, unless the cursor already follows one.
    public static func needsSpace(before: String) -> Bool {
        before.last.map { !$0.isWhitespace } ?? false
    }
}
