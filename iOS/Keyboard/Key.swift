/// One key on the Phono keyboard.
enum Key: Hashable {
    /// Types its text. On the letters page, the shift state sets the case.
    case character(String)
    case shift
    case delete
    case space
    case `return`
    case nextKeyboard
    /// Shows another page of keys.
    case page(Page)

    var isCharacter: Bool {
        if case .character = self { return true }
        return false
    }

    /// What holding the key offers, as on Apple's keyboard: the accents
    /// Spanish and English need, the most used first.
    var alternates: [String] {
        guard case .character(let text) = self else { return [] }
        return Self.alternates[text] ?? []
    }

    private static let alternates: [String: [String]] = [
        "a": ["á", "à", "ä", "â", "ã"],
        "e": ["é", "è", "ë", "ê"],
        "i": ["í", "ì", "ï", "î"],
        "o": ["ó", "ò", "ö", "ô", "õ"],
        "u": ["ú", "ü", "ù", "û"],
        "n": ["ñ"],
        "c": ["ç"],
        "?": ["¿"],
        "!": ["¡"],
    ]
}

/// The pages of keys, as on Apple's keyboard.
enum Page: Hashable {
    case letters
    case numbers
    case symbols

    /// Rows of keys, top to bottom.
    func rows(showsGlobe: Bool) -> [[Key]] {
        let bottom: [Key] = [.page(self == .letters ? .numbers : .letters)]
            + (showsGlobe ? [.nextKeyboard] : [])
            + [.space, .return]
        switch self {
        case .letters:
            return [
                Self.characters("qwertyuiop"),
                Self.characters("asdfghjkl"),
                [.shift] + Self.characters("zxcvbnm") + [.delete],
                bottom,
            ]
        case .numbers:
            return [
                Self.characters("1234567890"),
                Self.characters("-/:;()$&@\""),
                [.page(.symbols)] + Self.characters(".,?!'") + [.delete],
                bottom,
            ]
        case .symbols:
            return [
                Self.characters("[]{}#%^*+="),
                Self.characters("_\\|~<>€£¥•"),
                [.page(.numbers)] + Self.characters(".,?!'") + [.delete],
                bottom,
            ]
        }
    }

    private static func characters(_ keys: String) -> [Key] {
        keys.map { .character(String($0)) }
    }
}

enum Shift {
    case off
    /// The next letter only.
    case once
    case locked
}
