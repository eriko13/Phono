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
    private var speech: SpeechModel!
    private var hotkeys: HotkeyManager!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        speech = SpeechModel()
        let dictation = DictationController(settings: settings, speech: speech)

        hotkeys = HotkeyManager()
        hotkeys.onPress = { dictation.hotkeyPressed() }
        hotkeys.onRelease = { dictation.hotkeyReleased() }
        hotkeys.onInterrupt = { dictation.hotkeyInterrupted() }
        hotkeys.register(settings.hotkey)

        statusItem = StatusItemController(
            settings: settings, speech: speech, dictation: dictation, hotkeys: hotkeys)
        speech.onChange = { [weak self] in self?.statusItem.refresh() }
        dictation.onChange = { [weak self] in self?.statusItem.refresh() }

        // Ask up front, so the first dictation works.
        if Permissions.isMicrophoneUndetermined { Permissions.requestMicrophone() }
        if settings.output != .copy || settings.hotkey.isModifierOnly { Permissions.promptAccessibility() }

        speech.load()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.unregister()
    }
}
