import Foundation

/// Final shaping of a transcript before it reaches the user's text field.
public enum Transcript {
    /// Trim the model's output and optionally add one trailing space, so
    /// two dictations in a row do not run together. Returns nil when there
    /// is nothing worth pasting.
    public static func finalize(_ text: String, appendSpace: Bool) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return appendSpace ? trimmed + " " : trimmed
    }
}
