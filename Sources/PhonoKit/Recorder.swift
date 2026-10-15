import AVFoundation
#if os(macOS)
import CoreAudio
#endif
import Foundation
import PhonoCore

public enum RecorderError: Error, CustomStringConvertible {
    case noInputDevice
    /// The chosen microphone could not be selected (Core Audio status).
    case deviceUnavailable(OSStatus)

    public var description: String {
        switch self {
        case .noInputDevice: return "no microphone found"
        case .deviceUnavailable(let status): return "the chosen microphone is unavailable (\(status))"
        }
    }
}

/// Records an input device into 16 kHz mono floats.
///
/// A fresh `AVAudioEngine` per recording costs a few milliseconds and means a
/// device change (AirPods connecting, say) between two dictations just works.
@MainActor
public final class Recorder {
    private var engine: AVAudioEngine?
    private var sink: SampleSink?

    #if os(macOS)
    /// The Core Audio device to record from, or nil for the system default.
    /// Read each time the microphone opens.
    public var inputDevice: AudioDeviceID?
    #endif

    /// The microphone is on. It may be on without capturing, so that a
    /// capture can begin while the app is in the background.
    public var isOpen: Bool { engine != nil }
    public var isRecording: Bool { sink?.isCapturing ?? false }

    public init() {}

    /// Open the microphone and start capturing. `onLevel` gets a 0–1 loudness
    /// value for each audio buffer, and `onSamples` each captured buffer's
    /// 16 kHz samples, on the audio thread.
    public func start(
        onLevel: @escaping @Sendable (Float) -> Void,
        onSamples: (@Sendable ([Float]) -> Void)? = nil
    ) throws {
        try open(onLevel: onLevel, onSamples: onSamples)
        beginCapture()
    }

    /// Stop capturing, close the microphone, and return everything captured
    /// since `start`.
    public func stop() -> [Float] {
        let samples = endCapture()
        close()
        return samples
    }

    /// Turn the microphone on without keeping any audio. `onLevel` gets a
    /// 0–1 loudness value for each audio buffer, and `onSamples` each
    /// captured buffer's 16 kHz samples, on the audio thread.
    public func open(
        onLevel: @escaping @Sendable (Float) -> Void,
        onSamples: (@Sendable ([Float]) -> Void)? = nil
    ) throws {
        guard engine == nil else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        #if os(macOS)
        if let inputDevice { try use(inputDevice, for: input) }
        #endif
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }

        let sink = SampleSink(onLevel: onLevel, onSamples: onSamples)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: makeTapBlock(sink))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
        self.sink = sink
    }

    /// Start keeping audio. Does nothing if the microphone is not open.
    public func beginCapture() {
        sink?.beginCapture()
    }

    /// Stop keeping audio and return everything since `beginCapture`.
    public func endCapture() -> [Float] {
        sink?.endCapture() ?? []
    }

    #if os(macOS)
    /// Before the format is read: the format is the device's.
    private func use(_ device: AudioDeviceID, for input: AVAudioInputNode) throws {
        guard let unit = input.audioUnit else { return }
        var device = device
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw RecorderError.deviceUnavailable(status) }
    }
    #endif

    /// Turn the microphone off. Audio not yet taken with `endCapture` is lost.
    public func close() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.sink = nil
    }
}

/// Built outside the main actor on purpose. A closure written inside a
/// `@MainActor` type inherits that isolation, and Swift 6 traps when the
/// audio thread then calls it.
private func makeTapBlock(_ sink: SampleSink) -> AVAudioNodeTapBlock {
    { buffer, _ in sink.append(buffer) }
}

/// Converts and stores samples on the audio thread.
///
/// `append` runs only on the tap's thread, so `converter` needs no lock;
/// `samples` and `capturing` are shared with the main thread and are guarded.
final class SampleSink: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var capturing = false
    private var converter: AVAudioConverter?
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Model.sampleRate,
        channels: 1,
        interleaved: false
    )!
    private let onLevel: @Sendable (Float) -> Void
    private let onSamples: (@Sendable ([Float]) -> Void)?

    init(onLevel: @escaping @Sendable (Float) -> Void, onSamples: (@Sendable ([Float]) -> Void)?) {
        self.onLevel = onLevel
        self.onSamples = onSamples
        // About a minute of headroom before the array has to grow.
        samples.reserveCapacity(Int(Model.sampleRate) * 60)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.downmix = true
        }
        guard let converter else { return }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }

        // Feed this one buffer, then report "no data now" (not end of stream)
        // so the converter keeps its resampler state for the next buffer.
        let input = OneShotInput(buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            input.next(inputStatus)
        }
        guard status != .error, let channel = output.floatChannelData?[0] else { return }

        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        let kept = lock.withLock {
            if capturing { samples.append(contentsOf: chunk) }
            return capturing
        }
        onLevel(Self.level(of: chunk))
        if kept { onSamples?(chunk) }
    }

    var isCapturing: Bool {
        lock.withLock { capturing }
    }

    func beginCapture() {
        lock.withLock {
            samples = []
            capturing = true
        }
    }

    func endCapture() -> [Float] {
        lock.withLock {
            let out = samples
            samples = []
            capturing = false
            return out
        }
    }

    /// RMS mapped from −50…0 dBFS onto 0…1, for the level meter.
    static func level(of chunk: [Float]) -> Float {
        guard !chunk.isEmpty else { return 0 }
        let meanSquare = chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count)
        let decibels = 10 * log10(max(meanSquare, 1e-10))
        return min(max((decibels + 50) / 50, 0), 1)
    }
}

/// Hands the converter one buffer, once.
private final class OneShotInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
