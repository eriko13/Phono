import AVFoundation
import Observation
import PhonoCore
import PhonoKit
import UIKit

/// One dictation at a time: record, send the clip to the Phonon server, copy
/// the text or hand it to the keyboard.
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
    /// The transcript last put on the clipboard. Text sent to the keyboard is
    /// typed, not copied.
    private(set) var copied: String?
    /// The keyboard cannot use the microphone, so the app records for it.
    /// iOS does not let an app turn the microphone on from the background, so
    /// during a keyboard session the microphone stays on between clips.
    private(set) var keyboardSession = false

    let settings = Settings(store: .standard)
    /// Its Talk button records with the app in the background.
    let talk = TalkChannel()
    private let recorder = Recorder()
    /// The clip being recorded came from the keyboard, so its text goes there.
    private var forKeyboard = false
    /// The clip being recorded came from the Talk button. The system owns the
    /// audio session, and the app may be in the background.
    private var fromTalk = false
    private var idleTimer: Task<Void, Never>?

    /// The keyboard session ends this long after the last clip.
    static let keyboardIdle: Duration = .seconds(5 * 60)

    var hasServer: Bool { Server.baseURL(settings.serverURL) != nil }

    init() {
        KeyboardLink.observe(.toggle) { [weak self] in
            Task { await self?.keyboardToggle() }
        }
        KeyboardLink.observe(.ping) { [weak self] in
            self?.publish()
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated { self?.endKeyboardSession() }
        }
        talk.onActivate = { [weak self] in self?.talkActivated() }
        talk.onEnd = { [weak self] in
            Task { await self?.talkEnded() }
        }
        Task { await talk.start() }
        KeyboardLink.publish(.off, error: nil)
    }

    func toggle() async {
        switch state {
        case .recording: await finish()
        case .transcribing: return
        case .idle, .failed:
            forKeyboard = false
            await start()
        }
    }

    func copy(_ text: String) {
        UIPasteboard.general.string = text
        copied = text
    }

    /// The keyboard opened the app: turn the microphone on and start a clip.
    func startKeyboardSession() async {
        keyboardSession = true
        if state != .recording {
            forKeyboard = true
            await start()
        }
        if !recorder.isOpen { keyboardSession = false }
        restartIdleTimer()
        publish()
    }

    func endKeyboardSession() {
        guard keyboardSession else { return }
        keyboardSession = false
        idleTimer?.cancel()
        if state == .recording {
            _ = recorder.endCapture()
            level = 0
            state = .idle
        }
        if state != .transcribing { closeMic() }
        publish()
    }

    private func keyboardToggle() async {
        guard keyboardSession else { return }
        switch state {
        case .recording:
            await finish()
        case .transcribing:
            break
        case .idle, .failed:
            forKeyboard = true
            await start()
        }
        publish()
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
        idleTimer?.cancel()
        recorder.beginCapture()
        state = .recording
        publish()
    }

    private func finish() async {
        let samples = recorder.endCapture()
        if keyboardSession {
            restartIdleTimer()
        } else {
            closeMic()
        }
        level = 0
        await transcribe(samples)
        // The session may have ended while the clip was transcribing.
        if !keyboardSession { closeMic() }
    }

    /// Sends the clip to the server, then hands the text to the keyboard or
    /// copies it.
    private func transcribe(_ samples: [Float]) async {
        guard Model.duration(sampleCount: samples.count) >= 0.3 else {
            state = .idle
            return
        }
        guard let base = Server.baseURL(settings.serverURL) else {
            state = .failed("Set your server in Settings first.")
            return
        }

        state = .transcribing
        publish()
        do {
            let server = ServerEngine(base: base, key: settings.serverKey)
            let text = try await server.transcribe(samples)
            guard let text = Transcript.finalize(text, appendSpace: false) else {
                state = .idle
                return
            }
            transcripts.insert(text, at: 0)
            transcripts = Array(transcripts.prefix(10))
            if forKeyboard {
                KeyboardLink.send(text)
            }
            // The Phono keyboard may not be showing.
            if !forKeyboard || fromTalk {
                copy(text)
            }
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Talk button

    private func talkActivated() {
        guard state != .recording, state != .transcribing else { return }
        do {
            if !recorder.isOpen { try openRecorder() }
        } catch {
            state = .failed("Could not record: \(error.localizedDescription)")
            return
        }
        fromTalk = true
        forKeyboard = true
        idleTimer?.cancel()
        recorder.beginCapture()
        state = .recording
        publish()
    }

    private func talkEnded() async {
        guard fromTalk, state == .recording else { return }
        let samples = recorder.endCapture()
        // The system deactivates the session.
        if keyboardSession { restartIdleTimer() } else { recorder.close() }
        level = 0
        // iOS suspends the app soon after the Talk press ends.
        let task = UIApplication.shared.beginBackgroundTask()
        state = .transcribing
        publish()
        await transcribe(samples)
        fromTalk = false
        publish()
        UIApplication.shared.endBackgroundTask(task)
    }

    private func restartIdleTimer() {
        idleTimer?.cancel()
        guard keyboardSession else { return }
        idleTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.keyboardIdle)
            guard !Task.isCancelled, let self, self.state != .recording else { return }
            self.endKeyboardSession()
        }
    }

    /// Tells the keyboard where things stand.
    private func publish() {
        let shared: KeyboardLink.State
        var error: String?
        switch (keyboardSession || fromTalk, state) {
        case (false, _): shared = .off
        case (true, .recording): shared = .recording
        case (true, .transcribing): shared = .transcribing
        case (true, .idle): shared = .ready
        case (true, .failed(let message)):
            shared = .ready
            error = message
        }
        KeyboardLink.publish(shared, error: error)
    }

    private func openMic() throws {
        guard !recorder.isOpen else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            if keyboardSession {
                // Music keeps playing while the microphone waits in the
                // background.
                try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            } else {
                try session.setCategory(.record, mode: .default)
            }
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
