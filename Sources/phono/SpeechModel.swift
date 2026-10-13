import Foundation
import PhonoCore
import PhononCoreML

/// Phonon-2 on the Neural Engine, in this process. It loads once at launch
/// and stays in memory, so each dictation only pays for inference.
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

    private var engine: (any Transcribing)?

    var statusText: String {
        switch state {
        case .notInstalled: return "Model not downloaded — run Scripts/download-model.sh"
        case .loading(firstRun: false): return "Loading Phonon-2…"
        case .loading(firstRun: true): return "Preparing Phonon-2 for this Mac (once, 1–2 min)…"
        case .ready: return "Phonon-2 ready"
        case .failed(let reason): return "Phonon-2 failed: \(reason)"
        }
    }

    /// Nothing loaded and nothing loading: the menu offers to try again.
    var canLoad: Bool {
        switch state {
        case .notInstalled, .failed: return true
        case .loading, .ready: return false
        }
    }

    func load() {
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
                        if case .loading = self.state { self.state = .loading(firstRun: true) }
                    }
                }
            }
            Task { @MainActor in
                switch result {
                case .success(let runner):
                    self.engine = runner
                    self.state = .ready
                case .failure(let error):
                    self.state = .failed(error.localizedDescription)
                }
            }
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
