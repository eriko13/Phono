import Foundation
import PhonoCore

/// `phono transcribe <file>` and `phono status`. Settings live in the menu.
func runCLI(_ args: [String]) -> Int32 {
    let settings = Settings.shared
    let client = TranscriptionClient(baseURL: TranscriptionClient.loopback(port: settings.port))

    switch (args.first ?? "", args.count) {
    case ("transcribe", 2):
        return transcribe(path: args[1], client: client, hotwords: settings.hotwords)
    case ("status", 1):
        printStatus(settings: settings, client: client)
        return 0
    default:
        printError("""
            usage:
              phono                     start the menu-bar app
              phono transcribe <file>   print the text of a wav, flac, ogg, or aiff file
              phono status              show the engine, permissions, and settings
            """)
        return 2
    }
}

private func transcribe(path: String, client: TranscriptionClient, hotwords: [String]) -> Int32 {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard let audio = try? Data(contentsOf: url) else {
        printError("cannot read \(url.path)")
        return 1
    }
    do {
        print(try runBlocking {
            try await client.transcribe(audio: audio, filename: url.lastPathComponent, hotwords: hotwords)
        })
        return 0
    } catch {
        printError("transcription failed: \(error)\nIs Phono running?")
        return 1
    }
}

private func printStatus(settings: Settings, client: TranscriptionClient) {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let engine = Engine.locate(home: home, override: settings.enginePath)
    let healthy = (try? runBlocking { await client.isHealthy() }) ?? false
    let rows = [
        ("Engine", engine ?? "not installed (run Scripts/setup-engine.sh)"),
        ("Server", "\(client.baseURL.absoluteString), \(healthy ? "ready" : "not running")"),
        ("Accessibility", Permissions.isAccessibilityGranted ? "granted" : "not granted"),
        ("Microphone", Permissions.microphoneStatus),
        ("Shortcut", "\(settings.hotkey.title), \(settings.mode.title.lowercased())"),
        ("Hotwords", settings.hotwords.isEmpty ? "none" : settings.hotwords.joined(separator: ", ")),
    ]
    for (label, value) in rows {
        print("\(label.padding(toLength: 14, withPad: " ", startingAt: 0))\(value)")
    }
}

private func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Runs async work from the synchronous CLI, which has no run loop, by
/// parking the main thread until the work finishes.
private func runBlocking<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        do { box.result = .success(try await operation()) } catch { box.result = .failure(error) }
        done.signal()
    }
    done.wait()
    return try box.result!.get()
}

/// Written once by the task and read once after the semaphore, which orders
/// the two.
private final class ResultBox<T>: @unchecked Sendable {
    var result: Result<T, any Error>?
}
