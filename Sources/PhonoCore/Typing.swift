/// Rules of Apple's keyboard that the iPhone keyboard follows. Text in,
/// answers out, so they test on any platform.
public enum Typing {
    /// What the text field asks for, as `UITextAutocapitalizationType`.
    public enum Capitalization: Sendable {
        case none, words, sentences, allCharacters
    }

    /// Whether the next letter typed after `before` is a capital.
    public static func capitalizes(after before: String, _ mode: Capitalization) -> Bool {
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
            return ".!?".contains(end) || end.isNewline
        }
    }

    /// Two spaces after a word end the sentence: whether the second space,
    /// typed after `before`, becomes ". ".
    public static func spaceEndsSentence(after before: String, lastKeyWasSpace: Bool) -> Bool {
        lastKeyWasSpace && before.hasSuffix(" ")
            && before.dropLast().last.map { $0.isLetter || $0.isNumber } == true
    }

    /// Dictated text goes after a space, unless the cursor already follows one.
    public static func needsSpace(before: String) -> Bool {
        before.last.map { !$0.isWhitespace } ?? false
    }
}
