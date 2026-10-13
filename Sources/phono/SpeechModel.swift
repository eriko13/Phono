import Foundation
import PhonoCore
import PhononCoreML

/// Phonon-2, either on this Mac's Neural Engine or on a Phonon server. The
/// local model loads once and stays in memory, so each dictation only pays
/// for inference.
@MainActor
final class SpeechModel {
    enum State: Equatable {
        case notInstalled
        /// `firstRun`: macOS is compiling the model for this Mac's Neural
        /// Engine. That takes a minute or two and happens once.
        case loading(firstRun: Bool)
        case ready
        case failed(String)
    }

    private(set) var state: State = .loading(firstRun: false) {
        didSet { onChange?() }
    }
    var onChange: (() -> Void)?

    private let settings: Settings
    private var engine: (any Transcribing)?
    /// Bumped by every `load()`, so a slow load for an engine the user has
    /// since switched away from cannot win.
    private var generation = 0

    init(settings: Settings) {
        self.settings = settings
    }

    /// The server's host name, for the menu.
    var serverName: String {
        Server.baseURL(settings.serverURL)?.host ?? "server"
    }

    var statusText: String {
        switch (state, settings.engine) {
        case (.notInstalled, _): return "Model not downloaded — run Scripts/download-model.sh"
        case (.loading, .server): return "Connecting to \(serverName)…"
        case (.loading(firstRun: false), .local): return "Loading Phonon-2…"
        case (.loading(firstRun: true), _): return "Preparing Phonon-2 for this Mac (once, 1–2 min)…"
        case (.ready, .server): return "Phonon-2 on \(serverName)"
        case (.ready, .local): return "Phonon-2 ready"
        case (.failed(let reason), .server): return "\(serverName) failed: \(reason)"
        case (.failed(let reason), .local): return "Phonon-2 failed: \(reason)"
        }
    }

    /// Nothing loaded and nothing loading: the menu offers to try again.
    var canLoad: Bool {
        switch state {
        case .notInstalled, .failed: return true
        case .loading, .ready: return false
        }
    }

    /// Load the engine the settings name. Switching to the server frees the
    /// local model's memory.
    func load() {
        generation += 1
        engine = nil
        switch settings.engine {
        case .local: loadLocal(generation)
        case .server: connect(generation)
        }
    }

    private func loadLocal(_ generation: Int) {
        let directory = Model.directory(home: FileManager.default.homeDirectoryForCurrentUser)
        guard Model.isInstalled(at: directory) else {
            state = .notInstalled
            return
        }
        state = .loading(firstRun: false)
        Runner.queue.async {
            let result = Result {
                try Runner(directory: directory) { phase in
                    guard phase == "compiling" else { return }
                    Task { @MainActor in
                        guard generation == self.generation else { return }
                        if case .loading = self.state { self.state = .loading(firstRun: true) }
                    }
                }
            }
            Task { @MainActor in
                self.finish(generation, result.map { $0 })
            }
        }
    }

    /// The server is ready once it answers and accepts the key.
    private func connect(_ generation: Int) {
        guard let base = Server.baseURL(settings.serverURL) else {
            state = .failed(ServerError.noServer.description)
            return
        }
        state = .loading(firstRun: false)
        let server = ServerEngine(base: base, key: settings.serverKey)
        Task {
            do {
                try await server.checkConnection()
                finish(generation, .success(server))
            } catch {
                finish(generation, .failure(error))
            }
        }
    }

    private func finish(_ generation: Int, _ result: Result<any Transcribing, any Error>) {
        guard generation == self.generation else { return }
        switch result {
        case .success(let engine):
            self.engine = engine
            state = .ready
        case .failure(let error):
            state = .failed(error.localizedDescription)
        }
    }

    /// 16 kHz mono samples in, text out.
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let engine else { throw SpeechError.notReady }
        return try await engine.transcribe(samples)
    }
}

enum SpeechError: Error, CustomStringConvertible {
    case notReady

    var description: String { "the model is not loaded" }
}

/// Turns one clip of 16 kHz mono samples into text.
protocol Transcribing: Sendable {
    func transcribe(_ samples: [Float]) async throws -> String
}

/// Owns the `Transcriber` and runs it on one background queue, one clip at
/// a time. The queue is the only thread that touches it, which is why the
/// `@unchecked Sendable` is safe.
final class Runner: Transcribing, @unchecked Sendable {
    static let queue = DispatchQueue(label: "phono.speech", qos: .userInitiated)

    private let transcriber: Transcriber

    /// Blocks while the model loads. Call it on `queue`, or from the CLI.
    init(directory: URL, progress: ((String) -> Void)? = nil) throws {
        var options = Transcriber.Options()
        // Load the 15 s encoder now and the 5, 10, and 35 s ones in the
        // background. Until a smaller one is ready, the 15 s one serves.
        options.backgroundLoad = true
        if let progress { options.progress = { phase, _ in progress(phase) } }
        transcriber = try Transcriber(bundle: directory, options: options)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                continuation.resume(with: Result { try self.transcriber.transcribe(samples).text })
            }
        }
    }

    /// For the CLI, which has no run loop to wait on.
    func transcribeFile(_ url: URL) throws -> String {
        try transcriber.transcribe(url: url).text
    }
}
