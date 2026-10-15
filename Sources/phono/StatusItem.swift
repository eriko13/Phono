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
    private let microphoneMenu = makeMenu([])

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
        rebuildMicrophones()
        statusItem.menu?.items.forEach { ($0 as? MenuItem)?.reload() }
    }

    // MARK: - Items

    private func buildItems() -> [NSMenuItem] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return [
            MenuItem(liveTitle: { self.speech.statusText }),
            MenuItem("Load Phonon-2", isShown: { self.speech.canLoad && self.settings.engine == .local }) {
                self.speech.load()
            },
            MenuItem("Reconnect", isShown: { self.speech.canLoad && self.settings.engine == .server }) {
                self.speech.load()
            },
            MenuItem(liveTitle: { self.hint }),
            .separator(),
            choice(
                "Engine", Engine.allCases.map { (self.engineTitle($0), $0) },
                current: { self.settings.engine }, label: { self.engineTitle($0) },
                isShown: { !self.settings.serverURL.isEmpty }
            ) {
                guard $0 != self.settings.engine else { return }
                self.settings.engine = $0
                self.speech.load()
            },
            MenuItem(liveTitle: { "Microphone: \(self.microphoneTitle)" }, submenu: microphoneMenu),
            choice(
                "Mode", HotkeyMode.allCases.map { ($0.title, $0) },
                current: { self.settings.mode }, label: { $0.title }
            ) { self.settings.mode = $0 },
            MenuItem(liveTitle: { "Shortcuts: \(self.shortcutTitles)" }, submenu: shortcutMenu()),
            choice(
                "Output", Output.allCases.map { ($0.title, $0) },
                current: { self.settings.output }, label: { $0.title }
            ) {
                self.settings.output = $0
                if $0 != .copy { Permissions.promptAccessibility() }
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

    private func engineTitle(_ engine: Engine) -> String {
        engine == .server ? "\(engine.title) (\(speech.serverName))" : engine.title
    }

    private var hint: String {
        if let taken = hotkeys.taken.first { return "\(taken.title) is taken by another app" }
        let shortcuts = settings.hotkeys.map(\.title).joined(separator: " or ")
        if hotkeys.needsAccessibility { return "Allow Accessibility to use \(shortcuts)" }
        return "\(settings.mode == .hold ? "Hold" : "Press") \(shortcuts) to dictate"
    }

    private var shortcutTitles: String {
        settings.hotkeys.map(\.title).joined(separator: ", ")
    }

    /// A checkbox per shortcut, since any number of them can start a
    /// dictation. Grouped: lone modifiers, mouse buttons, key combinations.
    private func shortcutMenu() -> NSMenu {
        var items: [NSMenuItem] = []
        var group: String?
        for preset in HotkeyPreset.all {
            let kind = switch preset.trigger {
            case .modifier: "modifier"
            case .mouseButton: "mouse"
            case .chord: "chord"
            }
            if let group, group != kind { items.append(.separator()) }
            group = kind
            items.append(MenuItem(preset.title, isOn: { self.settings.hotkeys.contains(preset) }) {
                self.toggleHotkey(preset)
            })
        }
        return makeMenu(items)
    }

    /// A submenu of options with a checkmark on the current one. Its title
    /// shows the current choice.
    private func choice<T: Equatable>(
        _ title: String,
        _ options: [(String, T)],
        current: @escaping () -> T,
        label: @escaping (T) -> String,
        separatorBefore: Int? = nil,
        isShown: (() -> Bool)? = nil,
        select: @escaping (T) -> Void
    ) -> MenuItem {
        var items: [NSMenuItem] = options.map { name, value in
            MenuItem(name, isOn: { current() == value }) {
                select(value)
                self.refresh()
            }
        }
        if let separatorBefore { items.insert(.separator(), at: separatorBefore) }
        return MenuItem(liveTitle: { "\(title): \(label(current()))" }, isShown: isShown, submenu: makeMenu(items))
    }

    private func toggle(_ title: String, _ setting: ReferenceWritableKeyPath<Settings, Bool>) -> MenuItem {
        MenuItem(title, isOn: { self.settings[keyPath: setting] }) {
            self.settings[keyPath: setting].toggle()
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

    /// Devices come and go, so the list is read again each time the menu opens.
    private func rebuildMicrophones() {
        let inputs = AudioInputs.all
        let chosen = settings.inputDevice
        let systemName = AudioInputs.systemDefault.map { " (\($0.name))" } ?? ""

        var items: [NSMenuItem] = [
            MenuItem("System default\(systemName)", isOn: { chosen.isEmpty }) {
                self.selectMicrophone(nil)
            },
            .separator(),
        ]
        items += inputs.map { input in
            MenuItem(input.name, isOn: { input.uid == chosen }) { self.selectMicrophone(input) }
        }
        if !chosen.isEmpty, !inputs.contains(where: { $0.uid == chosen }) {
            let missing = MenuItem("\(settings.inputDeviceName) — not connected")
            missing.state = .on
            items.append(missing)
        }
        microphoneMenu.items = items
    }

    private var microphoneTitle: String {
        let chosen = settings.inputDevice
        if chosen.isEmpty { return "System default" }
        if AudioInputs.named(uid: chosen) == nil { return "System default (\(settings.inputDeviceName) not connected)" }
        return settings.inputDeviceName
    }

    // MARK: - Actions

    private func selectMicrophone(_ input: AudioInput?) {
        settings.inputDevice = input?.uid ?? ""
        settings.inputDeviceName = input?.name ?? ""
        refresh()
    }

    /// Adds or removes one shortcut. The last one stays: without a shortcut
    /// Phono could not be used.
    private func toggleHotkey(_ preset: HotkeyPreset) {
        var chosen = settings.hotkeys
        if let index = chosen.firstIndex(of: preset) {
            guard chosen.count > 1 else { return }
            chosen.remove(at: index)
        } else {
            chosen.append(preset)
        }
        settings.hotkeys = chosen
        hotkeys.register(settings.hotkeys)
        refresh()

        guard chosen.contains(preset) else { return }
        if preset.needsAccessibility { Permissions.promptAccessibility() }
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
