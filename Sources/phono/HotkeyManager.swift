import AppKit
import Carbon.HIToolbox
import PhonoCore

/// One global shortcut, with press and release.
///
/// - A chord (⌃⌥Space, F5, …) uses Carbon's `RegisterEventHotKey`. It is the
///   simplest reliable way to grab a system-wide chord, and it needs no
///   Accessibility permission.
/// - A modifier on its own (⌥, fn) cannot be registered with Carbon. For
///   those, global `NSEvent` monitors watch modifier changes, key-downs, and
///   clicks, and `ModifierTriggerState` decides what counts as a press. Global
///   monitors only receive events once Accessibility is granted.
@MainActor
final class HotkeyManager {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    /// A modifier trigger was used for another shortcut (⌥←, ⌥-click).
    var onInterrupt: () -> Void = {}

    private(set) var registered: HotkeyPreset?
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?

    private var modifierState: ModifierTriggerState?
    private var monitors: [Any] = []
    private var accessibilityPoll: Timer?
    /// Carbon does not auto-repeat hotkeys, but guard anyway: a second press
    /// without a release must not restart a recording.
    private var isDown = false

    private static let signature: OSType = {
        // 'PHNO'
        let chars: [UInt8] = [0x50, 0x48, 0x4E, 0x4F]
        return chars.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()

    /// Replace any current shortcut with `preset`. Returns false when another
    /// app already owns the chord.
    @discardableResult
    func register(_ preset: HotkeyPreset) -> Bool {
        unregisterKey()
        switch preset.trigger {
        case .chord(let keyCode, let modifiers):
            return registerChord(preset, keyCode: keyCode, modifiers: modifiers)
        case .modifier(let key):
            modifierState = ModifierTriggerState(key: key)
            registered = preset
            installMonitors()
            return true
        }
    }

    /// True while a modifier trigger is chosen but cannot work yet.
    var needsAccessibility: Bool {
        modifierState != nil && monitors.isEmpty
    }

    private func registerChord(_ preset: HotkeyPreset, keyCode: UInt32, modifiers: UInt32) -> Bool {
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            FileHandle.standardError.write(Data(
                "[HotkeyManager] RegisterEventHotKey failed (status \(status)) for \(preset.title)\n".utf8))
            registered = nil
            return false
        }
        hotKey = ref
        registered = preset
        return true
    }

    func unregister() {
        unregisterKey()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func unregisterKey() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        removeMonitors()
        modifierState = nil
        registered = nil
        // A release can be lost while re-registering; end any hold now.
        if isDown { released() }
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

                // Carbon calls back on the main thread; hop to the main actor.
                MainActor.assumeIsolated {
                    if kind == UInt32(kEventHotKeyPressed) {
                        manager.pressed()
                    } else if kind == UInt32(kEventHotKeyReleased) {
                        manager.released()
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
                self.handle(self.modifierState?.flagsChanged(keyCode: keyCode, flags: raw))
            }
        }
        let other = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { _ in
            MainActor.assumeIsolated {
                self.handle(self.modifierState?.otherInput())
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

    private func handle(_ event: ModifierTriggerState.Event?) {
        switch event {
        case .pressed: pressed()
        case .released: released()
        case .interrupted:
            guard isDown else { return }
            isDown = false
            onInterrupt()
        case nil: break
        }
    }

    // MARK: - Dispatch

    private func pressed() {
        guard !isDown else { return }
        isDown = true
        onPress()
    }

    private func released() {
        guard isDown else { return }
        isDown = false
        onRelease()
    }
}
