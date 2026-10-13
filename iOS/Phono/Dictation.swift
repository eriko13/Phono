import AVFoundation
import Observation
import PhonoCore
import PhonoKit
import UIKit

/// One dictation at a time: record, send the clip to the Phonon server, copy
/// the text.
@MainActor
@Observable
final class Dictation {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case failed(String)
    }

    private(set) var state: State = .idle
    /// 0–1 loudness of the latest audio buffer, for the level ring.
    private(set) var level: Float = 0
    /// Newest first. Kept for this launch only, like the Mac's Recent menu.
    private(set) var transcripts: [String] = []

    let settings = Settings(store: .standard)
    private let recorder = Recorder()

    var hasServer: Bool { Server.baseURL(settings.serverURL) != nil }

    func toggle() async {
        switch state {
        case .recording: await finish()
        case .transcribing: return
        case .idle, .failed: await start()
        }
    }

    func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    private func start() async {
        guard hasServer else {
            state = .failed("Set your server in Settings first.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .failed("Phono needs the microphone. Allow it in Settings › Apps › Phono.")
            return
        }
        do {
            try openMic()
        } catch {
            state = .failed("Could not record: \(error.localizedDescription)")
            return
        }
        recorder.beginCapture()
        state = .recording
    }

    private func finish() async {
        let samples = recorder.endCapture()
        closeMic()
        level = 0
        guard Model.duration(sampleCount: samples.count) >= 0.3 else {
            state = .idle
            return
        }
        guard let base = Server.baseURL(settings.serverURL) else {
            state = .failed("Set your server in Settings first.")
            return
        }

        state = .transcribing
        do {
            let server = ServerEngine(base: base, key: settings.serverKey)
            let text = try await server.transcribe(samples)
            guard let text = Transcript.finalize(text, appendSpace: false) else {
                state = .idle
                return
            }
            transcripts.insert(text, at: 0)
            transcripts = Array(transcripts.prefix(10))
            copy(text)
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func openMic() throws {
        guard !recorder.isOpen else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            try recorder.open { level in
                Task { @MainActor [weak self] in
                    guard let self, self.state == .recording else { return }
                    self.level = level
                }
            }
        } catch {
            deactivateSession()
            throw error
        }
    }

    private func closeMic() {
        recorder.close()
        deactivateSession()
    }

    /// Lets music or a podcast that the recording paused start again.
    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
