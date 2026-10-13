import Foundation

/// How a transcript reaches the active app.
public enum Output: String, CaseIterable, Sendable {
    /// Clipboard, then ⌘V. The old clipboard comes back after.
    case paste
    /// One key event per character. Slower, but works where ⌘V does not,
    /// and the clipboard stays as it was.
    case type
    /// Clipboard only.
    case copy

    public var title: String {
        switch self {
        case .paste: return "Paste"
        case .type: return "Type"
        case .copy: return "Copy only"
        }
    }
}

/// Every Phono setting, in one preferences domain.
///
/// The binary runs both inside Phono.app (bundle id = `domain`) and as a bare
/// CLI with no bundle id. `UserDefaults.standard` would give those two
/// different files, so the CLI names the suite explicitly.
public struct Settings: @unchecked Sendable {  // UserDefaults is thread-safe
    /// Matches `BUNDLE_ID` in Scripts/bundle.sh.
    public static let domain = "io.github.eriko13.phono"

    public static let shared: Settings = {
        if Bundle.main.bundleIdentifier == domain { return Settings(store: .standard) }
        return Settings(store: UserDefaults(suiteName: domain) ?? .standard)
    }()

    /// macOS system sounds offered for the end of a recording.
    public static let stopSounds = ["Bottle", "Morse", "Purr", "Tink", "Glass", "Pop"]

    public let store: UserDefaults

    public init(store: UserDefaults) {
        self.store = store
    }

    /// Stored key names. Changing one orphans users' saved values.
    enum Key: String {
        case mode = "hotkeyMode", hotkey, output, appendSpace, sounds, stopSound
        case engine, serverURL, serverKey
        /// Before `output`: true for paste, false for copy only.
        case legacyAutoPaste = "autoPaste"
    }

    public var mode: HotkeyMode {
        get { HotkeyMode(rawValue: value(.mode, "")) ?? .hold }
        nonmutating set { store.set(newValue.rawValue, forKey: Key.mode.rawValue) }
    }

    public var hotkey: HotkeyPreset {
        get { HotkeyPreset.named(value(.hotkey, "")) ?? .default }
        nonmutating set { store.set(newValue.name, forKey: Key.hotkey.rawValue) }
    }

    /// Paste and type need Accessibility. Without it, the text is only copied.
    public var output: Output {
        get {
            Output(rawValue: value(.output, ""))
                ?? (value(.legacyAutoPaste, true) ? .paste : .copy)
        }
        nonmutating set { store.set(newValue.rawValue, forKey: Key.output.rawValue) }
    }

    public var appendSpace: Bool {
        get { value(.appendSpace, true) }
        nonmutating set { store.set(newValue, forKey: Key.appendSpace.rawValue) }
    }

    public var sounds: Bool {
        get { value(.sounds, true) }
        nonmutating set { store.set(newValue, forKey: Key.sounds.rawValue) }
    }

    public var stopSound: String {
        get {
            let name = value(.stopSound, "")
            return Self.stopSounds.contains(name) ? name : Self.stopSounds[0]
        }
        nonmutating set { store.set(newValue, forKey: Key.stopSound.rawValue) }
    }

    public var engine: Engine {
        get { Engine(rawValue: value(.engine, "")) ?? .local }
        nonmutating set { store.set(newValue.rawValue, forKey: Key.engine.rawValue) }
    }

    /// As typed, for example `http://overmn:8000`. Read it through
    /// `Server.baseURL`.
    public var serverURL: String {
        get { value(.serverURL, "") }
        nonmutating set { store.set(newValue, forKey: Key.serverURL.rawValue) }
    }

    /// Sent as `Authorization: Bearer <key>`. Empty: no header.
    public var serverKey: String {
        get { value(.serverKey, "") }
        nonmutating set { store.set(newValue, forKey: Key.serverKey.rawValue) }
    }

    /// `object(forKey:)`, so a value never set reads as `fallback`, not as
    /// `false` or `0`.
    private func value<T>(_ key: Key, _ fallback: T) -> T {
        store.object(forKey: key.rawValue) as? T ?? fallback
    }
}
