import AVFoundation
import Observation
import PhonoCore
import PhonoKit
import UIKit

/// One dictation at a time: record, send the clip to the Phonon server, then
/// copy the text, or hand it to the keyboard when the clip came from the Talk
/// button.
@MainActor
@Observable
final class Dictation {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case failed(String)
    }

    private(set) var state: State = .idle {
        didSet { publish() }
    }
    /// 0–1 loudness of the latest audio buffer, for the level ring.
    private(set) var level: Float = 0
    /// Newest first. Kept for this launch only, like the Mac's Recent menu.
    private(set) var transcripts: [String] = []
    /// The transcript last put on the clipboard. Text sent to the keyboard is
    /// typed, not copied.
    private(set) var copied: String?

    let settings = Settings(store: .standard)
    /// Its Talk button records with the app in the background.
    let talk = TalkChannel()
    private let recorder = Recorder()
    /// The clip being recorded came from the Talk button. The system owns the
    /// audio session, and the app may be in the background.
    private var fromTalk = false

    var hasServer: Bool { Server.baseURL(settings.serverURL) != nil }

    init() {
        talk.onActivate = { [weak self] in self?.talkActivated() }
        talk.onEnd = { [weak self] in
            Task { await self?.talkEnded() }
        }
        Task { await talk.start() }
        publish()
    }

    func toggle() async {
        switch state {
        case .recording: await finish()
        case .transcribing: return
        case .idle, .failed: await start()
        }
    }

    func copy(_ text: String) {
        UIPasteboard.general.string = text
        copied = text
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
        if let text = await transcribe(samples) { copy(text) }
    }

    /// Sends the clip to the server. nil: no text, or it failed.
    private func transcribe(_ samples: [Float]) async -> String? {
        guard Model.duration(sampleCount: samples.count) >= 0.3 else {
            state = .idle
            return nil
        }
        guard let base = Server.baseURL(settings.serverURL) else {
            state = .failed("Set your server in Settings first.")
            return nil
        }

        state = .transcribing
        do {
            let server = ServerEngine(base: base, key: settings.serverKey)
            let text = try await server.transcribe(samples)
            guard let text = Transcript.finalize(text, appendSpace: false) else {
                state = .idle
                return nil
            }
            transcripts.insert(text, at: 0)
            transcripts = Array(transcripts.prefix(10))
            state = .idle
            return text
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    // MARK: Talk button

    private func talkActivated() {
        guard state != .recording, state != .transcribing else { return }
        do {
            try openRecorder()
        } catch {
            state = .failed("Could not record: \(error.localizedDescription)")
            return
        }
        fromTalk = true
        recorder.beginCapture()
        state = .recording
    }

    private func talkEnded() async {
        guard fromTalk, state == .recording else { return }
        fromTalk = false
        let samples = recorder.endCapture()
        // The system deactivates the session.
        recorder.close()
        level = 0
        // iOS suspends the app soon after the Talk press ends.
        let task = UIApplication.shared.beginBackgroundTask()
        if let text = await transcribe(samples) {
            // iOS does not let an app in the background use the clipboard,
            // so only the Phono keyboard can take the text.
            KeyboardLink.send(text)
        }
        UIApplication.shared.endBackgroundTask(task)
    }

    /// Tells the keyboard where things stand.
    private func publish() {
        switch state {
        case .idle: KeyboardLink.publish(.idle, error: nil)
        case .recording: KeyboardLink.publish(.recording, error: nil)
        case .transcribing: KeyboardLink.publish(.transcribing, error: nil)
        case .failed(let message): KeyboardLink.publish(.idle, error: message)
        }
    }

    private func openMic() throws {
        guard !recorder.isOpen else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            try openRecorder()
        } catch {
            deactivateSession()
            throw error
        }
    }

    /// Needs an active audio session.
    private func openRecorder() throws {
        try recorder.open { level in
            Task { @MainActor [weak self] in
                guard let self, self.state == .recording else { return }
                self.level = level
            }
        }
    }

    private func closeMic() {
        guard recorder.isOpen else { return }
        recorder.close()
        deactivateSession()
    }

    /// Lets music or a podcast that the recording paused start again.
    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
