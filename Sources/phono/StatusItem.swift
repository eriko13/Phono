import AppKit
import PhonoCore

/// The menu-bar icon and its menu: the whole UI apart from the recording pill.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings: Settings
    private let speech: SpeechModel
    private let dictation: DictationController
    private let hotkeys: HotkeyManager
    private let recentMenu = makeMenu([])

    init(settings: Settings, speech: SpeechModel, dictation: DictationController, hotkeys: HotkeyManager) {
        self.settings = settings
        self.speech = speech
        self.dictation = dictation
        self.hotkeys = hotkeys
        super.init()

        statusItem.isVisible = true   // older versions could hide it
        let menu = makeMenu(buildItems())
        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    func refresh() {
        let icon: StatusIcon.State = dictation.isRecording ? .recording
            : speech.state == .ready ? .ready : .unavailable
        statusItem.button?.image = StatusIcon.image(icon)

        rebuildRecent()
        statusItem.menu?.items.forEach { ($0 as? MenuItem)?.reload() }
    }

    // MARK: - Items

    private func buildItems() -> [NSMenuItem] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return [
            MenuItem(liveTitle: { self.speech.statusText }),
            MenuItem(liveTitle: { self.hint }),
            .separator(),
            choice(
                "Mode", HotkeyMode.allCases.map { ($0.title, $0) },
                current: { self.settings.mode }, label: { $0.title }
            ) { self.settings.mode = $0 },
            choice(
                "Shortcut", HotkeyPreset.all.map { ($0.title, $0) },
                current: { self.settings.hotkey }, label: { $0.title },
                separatorBefore: HotkeyPreset.all.firstIndex { !$0.isModifierOnly }
            ) { self.selectHotkey($0) },
            toggle("Paste into active app", \.autoPaste) {
                if self.settings.autoPaste { Permissions.promptAccessibility() }
            },
            toggle("Add trailing space", \.appendSpace),
            toggle("Play sounds", \.sounds),
            choice(
                "Stop sound", Settings.stopSounds.map { ($0, $0) },
                current: { self.settings.stopSound }, label: { $0 }
            ) {
                self.settings.stopSound = $0
                NSSound(named: NSSound.Name($0))?.play()   // the menu doubles as a preview
            },
            MenuItem("Recent", isShown: { !self.dictation.recent.isEmpty }, submenu: recentMenu),
            .separator(),
            MenuItem("Allow Accessibility…", isShown: { !Permissions.isAccessibilityGranted }) {
                Permissions.promptAccessibility()
                Permissions.openSettings(Permissions.accessibilityPane)
            },
            MenuItem("Allow Microphone…", isShown: { !Permissions.isMicrophoneGranted }) {
                Permissions.requestMicrophone()
            },
            .separator(),
            MenuItem("Phono \(version)"),
            MenuItem("Quit Phono", key: "q") { NSApp.terminate(nil) },
        ]
    }

    private var hint: String {
        let shortcut = settings.hotkey.title
        if hotkeys.registered == nil { return "\(shortcut) is taken by another app" }
        if hotkeys.needsAccessibility { return "Allow Accessibility to use \(shortcut)" }
        return "\(settings.mode == .hold ? "Hold" : "Press") \(shortcut) to dictate"
    }

    /// A submenu of options with a checkmark on the current one. Its title
    /// shows the current choice.
    private func choice<T: Equatable>(
        _ title: String,
        _ options: [(String, T)],
        current: @escaping () -> T,
        label: @escaping (T) -> String,
        separatorBefore: Int? = nil,
        select: @escaping (T) -> Void
    ) -> MenuItem {
        var items: [NSMenuItem] = options.map { name, value in
            MenuItem(name, isOn: { current() == value }) {
                select(value)
                self.refresh()
            }
        }
        if let separatorBefore { items.insert(.separator(), at: separatorBefore) }
        return MenuItem(liveTitle: { "\(title): \(label(current()))" }, submenu: makeMenu(items))
    }

    private func toggle(
        _ title: String,
        _ setting: ReferenceWritableKeyPath<Settings, Bool>,
        then: @escaping () -> Void = {}
    ) -> MenuItem {
        MenuItem(title, isOn: { self.settings[keyPath: setting] }) {
            self.settings[keyPath: setting].toggle()
            then()
            self.refresh()
        }
    }

    private func rebuildRecent() {
        recentMenu.items = dictation.recent.map { text in
            let title = text.count > 48 ? text.prefix(47) + "…" : Substring(text)
            return MenuItem(String(title)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }

    // MARK: - Actions

    private func selectHotkey(_ preset: HotkeyPreset) {
        settings.hotkey = preset
        hotkeys.register(preset)
        if preset.isModifierOnly { Permissions.promptAccessibility() }
        if preset.trigger == .modifier(.fn) { explainGlobeKey() }
    }

    /// macOS gives fn/Globe its own job (emoji picker, Apple dictation),
    /// which would fire on every dictation.
    private func explainGlobeKey() {
        let alert = NSAlert()
        alert.messageText = "Set the fn key to do nothing"
        alert.informativeText = """
            Otherwise macOS also reacts to fn, for example with the emoji \
            picker. In Keyboard settings, set "Press 🌐 key to" to "Do Nothing".
            """
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate()   // an accessory app is never frontmost
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openSettings(Permissions.keyboardPane)
        }
    }
}
