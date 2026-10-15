import AppKit
import Carbon.HIToolbox
import PhonoCore

/// Global shortcuts, with press and release. Any of them starts a dictation.
///
/// - A chord (⌃⌥Space, F5, …) uses Carbon's `RegisterEventHotKey`. It is the
///   simplest reliable way to grab a system-wide chord, and it needs no
///   Accessibility permission.
/// - A modifier on its own (⌥, fn) cannot be registered with Carbon. For
///   those, global `NSEvent` monitors watch modifier changes, key-downs, and
///   clicks, and `ModifierTriggerState` decides what counts as a press. Global
///   monitors only receive events once Accessibility is granted.
///
/// One shortcut holds the press at a time: another one pressed meanwhile is
/// ignored, and only the holder's release ends the press.
@MainActor
final class HotkeyManager {
    var onPress: (HotkeyPreset) -> Void = { _ in }
    var onRelease: (HotkeyPreset) -> Void = { _ in }
    /// A modifier trigger was used for another shortcut (⌥←, ⌥-click).
    var onInterrupt: (HotkeyPreset) -> Void = { _ in }

    /// The shortcuts that work, and those another app already owns.
    private(set) var registered: [HotkeyPreset] = []
    private(set) var taken: [HotkeyPreset] = []

    private var eventHandler: EventHandlerRef?
    /// Keyed by the `EventHotKeyID.id` each chord was registered with.
    private var chords: [UInt32: (preset: HotkeyPreset, ref: EventHotKeyRef)] = [:]

    private var modifiers: [(preset: HotkeyPreset, state: ModifierTriggerState)] = []
    private var monitors: [Any] = []
    private var accessibilityPoll: Timer?
    /// The shortcut that is down right now. Carbon does not auto-repeat
    /// hotkeys, but guard anyway: a second press without a release must not
    /// restart a recording.
    private var active: HotkeyPreset?

    private static let signature: OSType = {
        // 'PHNO'
        let chars: [UInt8] = [0x50, 0x48, 0x4E, 0x4F]
        return chars.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()

    /// Replace the current shortcuts with `presets`. A chord another app
    /// already owns ends up in `taken`.
    func register(_ presets: [HotkeyPreset]) {
        unregisterKeys()
        for (index, preset) in presets.enumerated() {
            switch preset.trigger {
            case .chord(let keyCode, let modifiers):
                let id = UInt32(index + 1)
                if registerChord(preset, keyCode: keyCode, modifiers: modifiers, id: id) {
                    registered.append(preset)
                } else {
                    taken.append(preset)
                }
            case .modifier(let key):
                modifiers.append((preset, ModifierTriggerState(key: key)))
                registered.append(preset)
            }
        }
        if !modifiers.isEmpty { installMonitors() }
    }

    /// True while a modifier trigger is chosen but cannot work yet.
    var needsAccessibility: Bool {
        !modifiers.isEmpty && monitors.isEmpty
    }

    private func registerChord(_ preset: HotkeyPreset, keyCode: UInt32, modifiers: UInt32, id: UInt32) -> Bool {
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            FileHandle.standardError.write(Data(
                "[HotkeyManager] RegisterEventHotKey failed (status \(status)) for \(preset.title)\n".utf8))
            return false
        }
        chords[id] = (preset, ref)
        return true
    }

    func unregister() {
        unregisterKeys()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func unregisterKeys() {
        for chord in chords.values { UnregisterEventHotKey(chord.ref) }
        chords = [:]
        removeMonitors()
        modifiers = []
        registered = []
        taken = []
        // A release can be lost while re-registering; end any hold now.
        if let active { released(active) }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        let specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userInfo -> OSStatus in
                guard let userInfo, let event else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                let kind = GetEventKind(event)
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let id = hotKeyID.id

                // Carbon calls back on the main thread; hop to the main actor.
                MainActor.assumeIsolated {
                    guard let preset = manager.chords[id]?.preset else { return }
                    if kind == UInt32(kEventHotKeyPressed) {
                        manager.pressed(preset)
                    } else if kind == UInt32(kEventHotKeyReleased) {
                        manager.released(preset)
                    }
                }
                return noErr
            },
            specs.count,
            specs,
            userInfo,
            &eventHandler
        )
    }

    // MARK: - Modifier triggers

    private func installMonitors() {
        removeMonitors()
        guard Permissions.isAccessibilityGranted else {
            // Monitors added before the grant stay deaf, so wait for it and
            // install then. No relaunch needed.
            accessibilityPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated {
                    guard Permissions.isAccessibilityGranted else { return }
                    self.installMonitors()
                }
            }
            return
        }

        let flags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            let keyCode = event.keyCode
            let raw = UInt(event.modifierFlags.rawValue)
            MainActor.assumeIsolated {
                for index in self.modifiers.indices {
                    let event = self.modifiers[index].state.flagsChanged(keyCode: keyCode, flags: raw)
                    self.handle(event, from: self.modifiers[index].preset)
                }
            }
        }
        let other = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { _ in
            MainActor.assumeIsolated {
                for index in self.modifiers.indices {
                    let event = self.modifiers[index].state.otherInput()
                    self.handle(event, from: self.modifiers[index].preset)
                }
            }
        }
        monitors = [flags, other].compactMap { $0 }
    }

    private func removeMonitors() {
        accessibilityPoll?.invalidate()
        accessibilityPoll = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
    }

    private func handle(_ event: ModifierTriggerState.Event?, from preset: HotkeyPreset) {
        switch event {
        case .pressed: pressed(preset)
        case .released: released(preset)
        case .interrupted:
            guard active == preset else { return }
            active = nil
            onInterrupt(preset)
        case nil: break
        }
    }

    // MARK: - Dispatch

    private func pressed(_ preset: HotkeyPreset) {
        guard active == nil else { return }
        active = preset
        onPress(preset)
    }

    private func released(_ preset: HotkeyPreset) {
        guard active == preset else { return }
        active = nil
        onRelease(preset)
    }
}
