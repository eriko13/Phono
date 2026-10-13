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
    default:
        printError("""
            usage:
              phono                     start the menu-bar app
              phono transcribe <file>   print the text of a wav, m4a, mp3, aiff, caf, or flac file
              phono status              show the model, permissions, and settings
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

private func printStatus(model: URL) {
    let settings = Settings.shared
    let rows = [
        ("Model", Model.isInstalled(at: model) ? model.path : "not downloaded (run Scripts/download-model.sh)"),
        ("Accessibility", Permissions.isAccessibilityGranted ? "granted" : "not granted"),
        ("Microphone", Permissions.microphoneStatus),
        ("Shortcut", "\(settings.hotkey.title), \(settings.mode.title.lowercased())"),
    ]
    for (label, value) in rows {
        print("\(label.padding(toLength: 14, withPad: " ", startingAt: 0))\(value)")
    }
}

private func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
