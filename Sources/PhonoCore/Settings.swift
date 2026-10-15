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

    /// macOS system sounds offered for a recording's cues.
    public static let soundNames = ["Bottle", "Morse", "Purr", "Tink", "Glass", "Pop"]

    public let store: UserDefaults

    public init(store: UserDefaults) {
        self.store = store
    }

    /// Stored key names. Changing one orphans users' saved values.
    enum Key: String {
        case mode = "hotkeyMode", hotkeys, output, appendSpace, sounds, startSound, stopSound
        case engine, serverURL, serverKey
        case inputDevice, inputDeviceName
        /// Before `output`: true for paste, false for copy only.
        case legacyAutoPaste = "autoPaste"
        /// Before `hotkeys`: the one shortcut's name.
        case legacyHotkey = "hotkey"
    }

    public var mode: HotkeyMode {
        get { HotkeyMode(rawValue: value(.mode, "")) ?? .hold }
        nonmutating set { store.set(newValue.rawValue, forKey: Key.mode.rawValue) }
    }

    /// Every shortcut that starts a dictation, in menu order. Never empty.
    public var hotkeys: [HotkeyPreset] {
        get {
            let names = Set(value(.hotkeys, [String]()))
            let chosen = HotkeyPreset.all.filter { names.contains($0.name) }
            if !chosen.isEmpty { return chosen }
            return [HotkeyPreset.named(value(.legacyHotkey, "")) ?? .default]
        }
        nonmutating set { store.set(newValue.map(\.name), forKey: Key.hotkeys.rawValue) }
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

    public var startSound: String {
        get { sound(.startSound, fallback: "Tink") }
        nonmutating set { store.set(newValue, forKey: Key.startSound.rawValue) }
    }

    public var stopSound: String {
        get { sound(.stopSound, fallback: "Bottle") }
        nonmutating set { store.set(newValue, forKey: Key.stopSound.rawValue) }
    }

    /// A name from `soundNames`, or `fallback`.
    private func sound(_ key: Key, fallback: String) -> String {
        let name = value(key, "")
        return Self.soundNames.contains(name) ? name : fallback
    }

    /// The microphone's Core Audio UID. Empty: the system default input.
    public var inputDevice: String {
        get { value(.inputDevice, "") }
        nonmutating set { store.set(newValue, forKey: Key.inputDevice.rawValue) }
    }

    /// The chosen microphone's name, for the menu while it is unplugged.
    public var inputDeviceName: String {
        get { value(.inputDeviceName, "") }
        nonmutating set { store.set(newValue, forKey: Key.inputDeviceName.rawValue) }
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
