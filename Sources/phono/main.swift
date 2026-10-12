import AppKit
import PhonoCore

// One binary, two modes: with arguments it is a CLI, without it is the
// menu-bar app. Launch Services and Xcode may pass `-psn_…` or `-NS…` flags,
// which mean "start the app".
let args = Array(CommandLine.arguments.dropFirst())
if let first = args.first, !first.hasPrefix("-psn"), !first.hasPrefix("-NS") {
    exit(runCLI(args))
}

let app = NSApplication.shared
// Also set by LSUIElement in Info.plist; repeated so a bare `swift run`
// build has no Dock icon either.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private var engine: EngineController!
    private var hotkeys: HotkeyManager!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = EngineController(settings: settings)
        let dictation = DictationController(settings: settings, engine: engine)

        hotkeys = HotkeyManager()
        hotkeys.onPress = { dictation.hotkeyPressed() }
        hotkeys.onRelease = { dictation.hotkeyReleased() }
        hotkeys.onInterrupt = { dictation.hotkeyInterrupted() }
        hotkeys.register(settings.hotkey)

        statusItem = StatusItemController(
            settings: settings, engine: engine, dictation: dictation, hotkeys: hotkeys)
        engine.onChange = { [weak self] in self?.statusItem.refresh() }
        dictation.onChange = { [weak self] in self?.statusItem.refresh() }

        // Ask up front, so the first dictation works.
        if Permissions.isMicrophoneUndetermined { Permissions.requestMicrophone() }
        if settings.autoPaste || settings.hotkey.isModifierOnly { Permissions.promptAccessibility() }

        engine.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.unregister()
        engine.stop()
    }
}
