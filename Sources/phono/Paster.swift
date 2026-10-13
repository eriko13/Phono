import AppKit
import ApplicationServices
import PhonoCore

/// Puts a transcript where the cursor is.
///
/// Paste: the text goes on the clipboard, then Phono posts ⌘V. After the
/// paste lands the previous clipboard comes back, so dictation does not eat
/// whatever the user had copied.
///
/// Type: Phono posts one key event per character and leaves the clipboard
/// alone.
///
/// Without Accessibility, both fall back to the clipboard.
@MainActor
enum Paster {
    enum Outcome {
        case inserted
        case copied
    }

    /// Long enough for the target app to read the clipboard on ⌘V.
    private static let restoreDelay: Duration = .milliseconds(600)
    /// Some apps drop characters that arrive with no gap between them.
    private static let keyGap: Duration = .milliseconds(2)
    /// The text still being typed. The next text waits for it.
    private static var typing: Task<Void, Never>?

    static func deliver(_ text: String, output: Output) -> Outcome {
        let canInsert = Permissions.isAccessibilityGranted
        if output == .type, canInsert {
            type(text)
            return .inserted
        }

        let pasteboard = NSPasteboard.general
        let willPaste = output == .paste && canInsert
        let saved = willPaste ? snapshot(pasteboard) : []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard willPaste else { return .copied }

        let ours = pasteboard.changeCount
        postCommandV()

        Task { @MainActor in
            try? await Task.sleep(for: restoreDelay)
            // If anything else wrote to the clipboard meanwhile, leave it.
            guard NSPasteboard.general.changeCount == ours, !saved.isEmpty else { return }
            restore(saved, to: NSPasteboard.general)
        }
        return .inserted
    }

    // MARK: - Clipboard snapshot

    /// One pasteboard item as (type, bytes) pairs. Plain values, so it can
    /// cross into the restore task.
    private struct SavedItem: Sendable {
        var entries: [(type: String, data: Data)]
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [SavedItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            SavedItem(entries: item.types.compactMap { kind in
                item.data(forType: kind).map { (type: kind.rawValue, data: $0) }
            })
        }
    }

    private static func restore(_ items: [SavedItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { saved -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for entry in saved.entries {
                item.setData(entry.data, forType: NSPasteboard.PasteboardType(entry.type))
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }

    // MARK: - Keystroke

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 9   // kVK_ANSI_V
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: isDown)
            // Set the flags outright, so modifiers still held from the
            // dictation shortcut (⌃⌥) do not turn this into ⌃⌥⌘V.
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Each event carries one character, not a key code, so the keyboard
    /// layout does not matter. One character per event, because some apps
    /// read only the first character of a longer string.
    private static func type(_ text: String) {
        typing = Task { [previous = typing] in
            await previous?.value
            let source = CGEventSource(stateID: .combinedSessionState)
            for character in text {
                let units = Array(character.utf16)
                for isDown in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown)
                    // No modifiers, so a held ⌃ or ⌥ does not turn a letter
                    // into a shortcut.
                    event?.flags = []
                    event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                    event?.post(tap: .cghidEventTap)
                }
                try? await Task.sleep(for: keyGap)
            }
        }
    }
}
