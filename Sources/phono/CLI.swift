import Foundation
import PhonoCore

/// `phono transcribe <file>` and `phono status`. Settings live in the menu.
func runCLI(_ args: [String]) -> Int32 {
    let model = Model.directory(home: FileManager.default.homeDirectoryForCurrentUser)

    switch (args.first ?? "", args.count) {
    case ("transcribe", 2):
        return transcribe(path: args[1], model: model)
    case ("status", 1):
        printStatus(model: model)
        return 0
    case ("server", 2...3):
        return setServer(Array(args.dropFirst()))
    default:
        printError("""
            usage:
              phono                     start the menu-bar app
              phono transcribe <file>   print the text of a wav, m4a, mp3, aiff, caf, or flac file
              phono status              show the model, permissions, and settings
              phono server <url> [key]  dictate through a Phonon server, such as http://overmn:8000
              phono server off          dictate on this Mac again
            """)
        return 2
    }
}

/// Loads the model in this process, so the menu-bar app need not run.
private func transcribe(path: String, model: URL) -> Int32 {
    guard Model.isInstalled(at: model) else {
        printError("Phonon-2 is not downloaded. Run Scripts/download-model.sh.")
        return 1
    }
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    do {
        let runner = try Runner(directory: model) { phase in
            if phase == "compiling" { printError("Preparing Phonon-2 for this Mac (once, 1–2 min)…") }
        }
        print(try runner.transcribeFile(url))
        return 0
    } catch {
        printError("transcription failed: \(error.localizedDescription)")
        return 1
    }
}

/// The menu has no text fields, so the server is set here. The running app
/// picks it up when Engine is chosen in the menu, or on its next launch.
private func setServer(_ args: [String]) -> Int32 {
    let settings = Settings.shared
    if args == ["off"] {
        settings.engine = .local
        print("Engine: This Mac. Quit and reopen Phono to switch now.")
        return 0
    }
    guard let base = Server.baseURL(args[0]) else {
        printError("not a server URL: \(args[0]) (expected something like http://overmn:8000)")
        return 2
    }
    settings.serverURL = base.absoluteString
    if args.count == 2 { settings.serverKey = args[1] }
    settings.engine = .server
    print("Engine: \(base.absoluteString). Quit and reopen Phono, or choose Engine › Server in its menu.")
    return 0
}

private func printStatus(model: URL) {
    let settings = Settings.shared
    let rows = [
        ("Engine", settings.engine == .server ? settings.serverURL : Engine.local.title),
        ("Model", Model.isInstalled(at: model) ? model.path : "not downloaded (run Scripts/download-model.sh)"),
        ("Accessibility", Permissions.isAccessibilityGranted ? "granted" : "not granted"),
        ("Microphone", Permissions.microphoneStatus),
        ("Shortcut", "\(settings.hotkey.title), \(settings.mode.title.lowercased())"),
        ("Output", settings.output.title),
    ]
    for (label, value) in rows {
        print("\(label.padding(toLength: 14, withPad: " ", startingAt: 0))\(value)")
    }
}

private func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
