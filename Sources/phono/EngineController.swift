import Foundation
import PhonoCore

/// Starts `fermion serve phonon-2` on loopback and keeps it warm.
///
/// If something already answers `/health` on the port (a server you started
/// yourself, or one left over from a crash), Phono uses it and does not own
/// it. Otherwise Phono launches the engine as a child process and stops it on
/// quit.
@MainActor
final class EngineController {
    enum State: Equatable {
        case stopped
        case notInstalled
        case starting
        case ready
        case failed(String)
    }

    private(set) var state: State = .stopped {
        didSet { onChange?() }
    }
    var onChange: (() -> Void)?

    /// True when the server was already running and Phono did not launch it.
    private(set) var isExternal = false
    private(set) var client: TranscriptionClient

    private let settings: Settings
    private var process: Process?
    private var startTask: Task<Void, Never>?

    /// The first start can include the model download (164 MB) before the
    /// 10–40 s load, so allow a generous window.
    private static let startTimeout: TimeInterval = 300

    init(settings: Settings) {
        self.settings = settings
        client = TranscriptionClient(baseURL: TranscriptionClient.loopback(port: settings.port))
    }

    var statusText: String {
        switch state {
        case .stopped: return "Engine: stopped"
        case .notInstalled: return "Engine: not installed"
        case .starting: return "Engine: loading Phonon-2…"
        case .ready: return isExternal ? "Engine: ready (external)" : "Engine: ready"
        case .failed(let reason): return "Engine: \(reason)"
        }
    }

    func start() {
        startTask?.cancel()
        let port = settings.port
        client = TranscriptionClient(baseURL: TranscriptionClient.loopback(port: port))
        isExternal = false
        state = .starting

        let client = self.client
        startTask = Task { [weak self] in
            if await client.isHealthy() {
                self?.becomeReady(external: true)
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.launch(port: port)
            guard self.state == .starting else { return }

            let deadline = Date().addingTimeInterval(Self.startTimeout)
            while Date() < deadline, !Task.isCancelled {
                if await client.isHealthy() {
                    self.becomeReady(external: false)
                    return
                }
                // The exit handler has already reported a crash.
                guard self.process?.isRunning == true else { return }
                try? await Task.sleep(for: .milliseconds(500))
            }
            if !Task.isCancelled {
                self.terminate()
                self.state = .failed("did not start — see engine log")
            }
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        terminate()
        state = .stopped
    }

    func restart() {
        stop()
        start()
    }

    // MARK: - Process

    private func becomeReady(external: Bool) {
        isExternal = external
        state = .ready
    }

    private func launch(port: Int) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let path = Engine.locate(home: home, override: settings.enginePath) else {
            state = .notInstalled
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = Engine.serveArguments(port: port)

        // An app launched from Finder gets a bare PATH. Put the venv's bin
        // first so the engine finds its own Python tools.
        var environment = ProcessInfo.processInfo.environment
        let binDirectory = (path as NSString).deletingLastPathComponent
        environment["PATH"] = [binDirectory, "/opt/homebrew/bin", "/usr/local/bin",
                               environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        environment["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

        let log = openLog(home: home)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log ?? FileHandle.nullDevice
        process.standardError = log ?? FileHandle.nullDevice

        let id = ObjectIdentifier(process)
        // Strong capture is fine: the controller lives as long as the app.
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { @MainActor in self.processExited(id: id, status: status) }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            state = .failed("could not launch (\(error.localizedDescription))")
        }
    }

    private func processExited(id: ObjectIdentifier, status: Int32) {
        guard let process, ObjectIdentifier(process) == id else { return }
        self.process = nil
        // `stop()` clears `process` first, so reaching here means a crash.
        state = .failed("exited with status \(status) — see engine log")
    }

    private func terminate() {
        guard let process else { return }
        self.process = nil
        if process.isRunning { process.terminate() }
    }

    /// A fresh log per launch, at ~/Library/Logs/Phono/engine.log.
    private func openLog(home: URL) -> FileHandle? {
        let url = Engine.logFile(home: home)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
    }
}
