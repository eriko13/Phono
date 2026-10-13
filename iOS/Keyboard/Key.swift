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
