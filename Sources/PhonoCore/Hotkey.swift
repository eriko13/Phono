/// How the shortcut drives recording.
public enum HotkeyMode: String, CaseIterable, Sendable {
    /// Hold the shortcut to talk; release to transcribe.
    case hold
    /// Press once to start, press again to transcribe.
    case toggle

    public var title: String {
        switch self {
        case .hold: return "Hold to talk"
        case .toggle: return "Press to start / stop"
        }
    }
}

/// What starts a dictation.
public enum HotkeyTrigger: Equatable, Sendable {
    /// A key plus modifiers, registered with Carbon. Key codes and modifier
    /// masks are the Carbon values (`kVK_*`, `controlKey`, ...), written as
    /// numbers so this file needs no Carbon import.
    case chord(keyCode: UInt32, modifiers: UInt32)
    /// A modifier key on its own, such as ⌥ or fn. Carbon cannot register
    /// these, so the app watches modifier changes instead (needs
    /// Accessibility).
    case modifier(ModifierKey)
    /// An extra mouse button, numbered like `NSEvent.buttonNumber`: 2 is
    /// the middle button, 3 and 4 the side buttons (back and forward). The
    /// app takes the click, so a browser does not also go back (needs
    /// Accessibility).
    case mouseButton(Int)
}

/// A shortcut Phono can use.
public struct HotkeyPreset: Sendable, Equatable {
    public let name: String
    public let title: String
    public let trigger: HotkeyTrigger

    public var isModifierOnly: Bool {
        if case .modifier = trigger { return true }
        return false
    }

    /// Lone modifiers and mouse buttons are seen through event monitors,
    /// which macOS allows only with Accessibility.
    public var needsAccessibility: Bool {
        if case .chord = trigger { return false }
        return true
    }

    static let cmd: UInt32 = 0x0100
    static let shift: UInt32 = 0x0200
    static let option: UInt32 = 0x0800
    static let control: UInt32 = 0x1000
    static let space: UInt32 = 49

    public static let all: [HotkeyPreset] = [
        HotkeyPreset(name: "option", title: "⌥ Option", trigger: .modifier(.option)),
        HotkeyPreset(name: "right-option", title: "Right ⌥ Option", trigger: .modifier(.rightOption)),
        HotkeyPreset(name: "fn", title: "fn (Globe)", trigger: .modifier(.fn)),
        HotkeyPreset(name: "mouse-4", title: "Mouse button 4 (back)", trigger: .mouseButton(3)),
        HotkeyPreset(name: "mouse-5", title: "Mouse button 5 (forward)", trigger: .mouseButton(4)),
        HotkeyPreset(name: "ctrl-opt-space", title: "⌃⌥Space",
                     trigger: .chord(keyCode: space, modifiers: control | option)),
        HotkeyPreset(name: "opt-space", title: "⌥Space",
                     trigger: .chord(keyCode: space, modifiers: option)),
        HotkeyPreset(name: "ctrl-shift-space", title: "⌃⇧Space",
                     trigger: .chord(keyCode: space, modifiers: control | shift)),
        HotkeyPreset(name: "cmd-shift-space", title: "⌘⇧Space",
                     trigger: .chord(keyCode: space, modifiers: cmd | shift)),
        HotkeyPreset(name: "f5", title: "F5", trigger: .chord(keyCode: 96, modifiers: 0)),
    ]

    public static let `default` = all[0]

    public static func named(_ name: String) -> HotkeyPreset? {
        all.first { $0.name == name }
    }
}

/// A modifier key that can start dictation on its own.
public enum ModifierKey: String, Sendable, CaseIterable {
    /// Either Option key.
    case option
    case rightOption
    /// fn, or the Globe key on newer keyboards.
    case fn

    /// Virtual key codes (`kVK_Option`, `kVK_RightOption`, `kVK_Function`).
    var keyCodes: Set<UInt16> {
        switch self {
        case .option: return [58, 61]
        case .rightOption: return [61]
        case .fn: return [63]
        }
    }

    /// The device-independent flag this key sets.
    var ownFlag: UInt {
        switch self {
        case .option, .rightOption: return ModifierFlags.option
        case .fn: return ModifierFlags.function
        }
    }

    func isDown(_ flags: UInt) -> Bool {
        switch self {
        case .option: return flags & ModifierFlags.option != 0
        case .rightOption: return flags & ModifierFlags.rightOptionDevice != 0
        case .fn: return flags & ModifierFlags.function != 0
        }
    }

    /// Modifiers that turn a press of this key into some other shortcut.
    var otherFlags: UInt {
        ModifierFlags.chordModifiers & ~ownFlag
    }
}

/// `NSEvent.ModifierFlags` raw values, so this file needs no AppKit.
public enum ModifierFlags {
    public static let shift: UInt = 1 << 17
    public static let control: UInt = 1 << 18
    public static let option: UInt = 1 << 19
    public static let command: UInt = 1 << 20
    public static let function: UInt = 1 << 23
    /// Device-dependent bit for the right Option key (`NX_DEVICERALTKEYMASK`).
    public static let rightOptionDevice: UInt = 0x40

    static let chordModifiers = shift | control | option | command | function
}

/// Turns raw modifier and key events into dictation events for a single
/// modifier key.
///
/// Option and fn are also parts of normal shortcuts (⌥←, fn-F5, ⌥-click).
/// So a press counts only while the key is alone: when another key, another
/// modifier, or a click joins it, the press becomes `interrupted` and its
/// release is swallowed.
public struct ModifierTriggerState: Sendable {
    public enum Event: Equatable, Sendable {
        case pressed
        case released
        /// The key was used for some other shortcut. Discard any recording.
        case interrupted
    }

    public let key: ModifierKey
    public private(set) var isDown = false
    private var isInterrupted = false

    public init(key: ModifierKey) {
        self.key = key
    }

    /// Feed every `flagsChanged` event.
    public mutating func flagsChanged(keyCode: UInt16, flags: UInt) -> Event? {
        guard key.keyCodes.contains(keyCode) else {
            // Another modifier changed while ours is held.
            guard isDown, flags & key.otherFlags != 0 else { return nil }
            return interrupt()
        }

        let down = key.isDown(flags)
        if down, !isDown {
            isDown = true
            // Pressed while ⌘, ⌃, or ⇧ was already held: part of a chord.
            isInterrupted = flags & key.otherFlags != 0
            return isInterrupted ? nil : .pressed
        }
        if !down, isDown {
            isDown = false
            return isInterrupted ? nil : .released
        }
        return nil
    }

    /// Feed every key-down and mouse-down event.
    public mutating func otherInput() -> Event? {
        guard isDown else { return nil }
        return interrupt()
    }

    private mutating func interrupt() -> Event? {
        guard !isInterrupted else { return nil }
        isInterrupted = true
        return .interrupted
    }
}
