import Foundation

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
        case mode = "hotkeyMode", hotkey, autoPaste, appendSpace, sounds, stopSound
    }

    public var mode: HotkeyMode {
        get { HotkeyMode(rawValue: value(.mode, "")) ?? .hold }
        nonmutating set { store.set(newValue.rawValue, forKey: Key.mode.rawValue) }
    }

    public var hotkey: HotkeyPreset {
        get { HotkeyPreset.named(value(.hotkey, "")) ?? .default }
        nonmutating set { store.set(newValue.name, forKey: Key.hotkey.rawValue) }
    }

    /// Paste into the active app (needs Accessibility). Off: clipboard only.
    public var autoPaste: Bool {
        get { value(.autoPaste, true) }
        nonmutating set { store.set(newValue, forKey: Key.autoPaste.rawValue) }
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

    /// `object(forKey:)`, so a value never set reads as `fallback`, not as
    /// `false` or `0`.
    private func value<T>(_ key: Key, _ fallback: T) -> T {
        store.object(forKey: key.rawValue) as? T ?? fallback
    }
}
