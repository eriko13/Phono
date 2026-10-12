import AppKit
import PhonoCore

/// Shortcut → record → transcribe → paste.
@MainActor
final class DictationController {
    private enum Phase {
        case idle
        case recording
        /// Short post-roll after the key comes up, so the last syllable is kept.
        case stopping
    }

    var onChange: (() -> Void)?
    private(set) var recent: [String] = []

    private let settings: Settings
    private let engine: EngineController
    private let recorder = Recorder()
    private let hud = HUD()
    private var phase: Phase = .idle {
        didSet { onChange?() }
    }

    private static let postRoll: Duration = .milliseconds(150)
    /// Shorter clips are almost always an accidental tap of the shortcut.
    private static let minimumSeconds = 0.3
    private static let recentLimit = 10
    /// A lone modifier is also part of everyday shortcuts. Record from the
    /// first instant, but show the pill and play the sound only once the key
    /// has been held this long, so ⌥← and quick taps stay invisible.
    private static let revealDelay: Duration = .milliseconds(250)

    /// The trigger key is down right now.
    private var held = false
    /// The user has seen (and heard) that recording started.
    private var revealed = true
    private var revealTask: Task<Void, Never>?

    init(settings: Settings, engine: EngineController) {
        self.settings = settings
        self.engine = engine
    }

    var isRecording: Bool { phase == .recording }

    // MARK: - Shortcut
    //
    // Hold mode: press starts, release stops.
    // Toggle mode: a chord's press flips. A lone modifier flips on release,
    // and only after a clean tap, so ⌥← never starts a recording.

    func hotkeyPressed() {
        held = true
        let modifierOnly = settings.hotkey.isModifierOnly
        switch settings.mode {
        case .hold:
            begin(quiet: modifierOnly)
        case .toggle:
            if !modifierOnly { toggle() }
        }
    }

    func hotkeyReleased() {
        held = false
        switch settings.mode {
        case .hold:
            finish()
        case .toggle:
            if settings.hotkey.isModifierOnly { toggle() }
        }
    }

    /// The modifier was used for another shortcut: drop the recording.
    func hotkeyInterrupted() {
        held = false
        if settings.mode == .hold { cancel() }
    }

    private func toggle() {
        if phase == .recording { finish() } else { begin(quiet: false) }
    }

    // MARK: - Recording

    private struct Problem: Sendable {
        let message: String
        let symbol: String
        var asksForMicrophone = false
    }

    private func readinessProblem() -> Problem? {
        switch engine.state {
        case .ready:
            break
        case .starting:
            return Problem(message: "Phonon-2 is still loading…", symbol: "hourglass")
        case .notInstalled:
            return Problem(message: "Engine not installed — run Scripts/setup-engine.sh",
                           symbol: "exclamationmark.circle")
        case .stopped, .failed:
            return Problem(message: "Engine is not running — see the menu", symbol: "exclamationmark.circle")
        }

        if Permissions.isMicrophoneGranted { return nil }
        let message = Permissions.isMicrophoneUndetermined
            ? "Allow microphone access, then try again"
            : "Microphone access is off"
        return Problem(message: message, symbol: "mic.slash", asksForMicrophone: true)
    }

    private func present(_ problem: Problem) {
        hud.flash(problem.message, symbol: problem.symbol)
        if problem.asksForMicrophone { Permissions.requestMicrophone() }
    }

    func begin(quiet: Bool) {
        guard phase == .idle else { return }

        if let problem = readinessProblem() {
            guard quiet else { return present(problem) }
            // Only speak up if the key is still held: a real attempt.
            Task {
                try? await Task.sleep(for: Self.revealDelay)
                if held { present(problem) }
            }
            return
        }

        let hud = self.hud
        do {
            try recorder.start { level in
                Task { @MainActor in hud.setLevel(level) }
            }
        } catch {
            hud.flash("Could not record: \(error)", symbol: "mic.slash")
            return
        }
        phase = .recording

        if quiet {
            revealed = false
            revealTask = Task {
                try? await Task.sleep(for: Self.revealDelay)
                guard !Task.isCancelled, phase == .recording else { return }
                reveal()
            }
        } else {
            reveal()
        }
    }

    private func reveal() {
        revealed = true
        play("Tink")
        hud.showListening()
    }

    func finish() {
        guard phase == .recording else { return }
        // Released before the pill showed: a tap, not a dictation.
        guard revealed else { return cancel() }
        phase = .stopping

        Task {
            try? await Task.sleep(for: Self.postRoll)
            let samples = recorder.stop()
            phase = .idle
            play(settings.stopSound)
            await transcribe(samples)
        }
    }

    /// Stop and throw the audio away.
    func cancel() {
        guard phase == .recording else { return }
        revealTask?.cancel()
        revealTask = nil
        _ = recorder.stop()
        phase = .idle
        if revealed { hud.hide() }
        revealed = true
    }

    // MARK: - Transcription

    private func transcribe(_ samples: [Float]) async {
        guard WAV.duration(sampleCount: samples.count) >= Self.minimumSeconds else {
            updateHUD { $0.hide() }
            return
        }
        updateHUD { $0.showWorking() }

        let wav = WAV.encode(samples: samples)
        let client = engine.client
        let hotwords = settings.hotwords
        do {
            let raw = try await client.transcribe(audio: wav, hotwords: hotwords)
            guard let text = Transcript.finalize(raw, appendSpace: settings.appendSpace) else {
                updateHUD { $0.flash("No speech heard", symbol: "waveform.slash") }
                return
            }
            remember(text)
            switch Paster.deliver(text, autoPaste: settings.autoPaste) {
            case .pasted:
                updateHUD { $0.hide() }
            case .copied:
                let message = settings.autoPaste
                    ? "Copied — allow Accessibility to paste"
                    : "Copied to clipboard"
                updateHUD { $0.flash(message, symbol: "doc.on.clipboard", seconds: 1.6) }
            }
        } catch {
            FileHandle.standardError.write(Data("[Dictation] \(error)\n".utf8))
            updateHUD { $0.flash("Transcription failed — \(error)") }
        }
    }

    /// A new recording may start while an older clip is still transcribing.
    /// Its "Listening" pill wins; the older clip must not replace it.
    private func updateHUD(_ change: (HUD) -> Void) {
        guard phase == .idle else { return }
        change(hud)
    }

    private func remember(_ text: String) {
        recent.insert(text.trimmingCharacters(in: .whitespaces), at: 0)
        if recent.count > Self.recentLimit { recent.removeLast() }
        onChange?()
    }

    private func play(_ name: String) {
        guard settings.sounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
