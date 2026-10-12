import Foundation

/// Final shaping of a transcript before it reaches the user's text field.
public enum Transcript {
    /// Trim the engine's output and optionally add one trailing space, so
    /// two dictations in a row do not run together. Returns nil when there
    /// is nothing worth pasting.
    public static func finalize(_ text: String, appendSpace: Bool) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return appendSpace ? trimmed + " " : trimmed
    }
}

/// Vocabulary that biases recognition toward names and jargon.
public enum Hotwords {
    /// The engine accepts up to this many terms per request.
    public static let limit = 25

    /// Split on commas and newlines, trim, drop blanks and `#` comments,
    /// de-duplicate case-insensitively, and cap at `limit`.
    public static func parse(_ raw: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for piece in raw.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            let term = piece.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty, !term.hasPrefix("#") else { continue }
            guard seen.insert(term.lowercased()).inserted else { continue }
            out.append(term)
            if out.count == limit { break }
        }
        return out
    }
}
