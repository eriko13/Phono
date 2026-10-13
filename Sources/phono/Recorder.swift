import AVFoundation
import Foundation
import PhonoCore

enum RecorderError: Error, CustomStringConvertible {
    case noInputDevice

    var description: String {
        switch self {
        case .noInputDevice: return "no microphone found"
        }
    }
}

/// Records the default input device into 16 kHz mono floats.
///
/// A fresh `AVAudioEngine` per recording costs a few milliseconds and means a
/// device change (AirPods connecting, say) between two dictations just works.
@MainActor
final class Recorder {
    private var engine: AVAudioEngine?
    private var sink: SampleSink?

    var isRecording: Bool { engine != nil }

    /// Start capturing. `onLevel` gets a 0–1 loudness value for each audio
    /// buffer, and `onSamples` the buffer's 16 kHz samples, on the audio
    /// thread.
    func start(
        onLevel: @escaping @Sendable (Float) -> Void,
        onSamples: (@Sendable ([Float]) -> Void)? = nil
    ) throws {
        guard engine == nil else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
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

    /// Stop and return everything captured since `start`.
    func stop() -> [Float] {
        guard let engine, let sink else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.sink = nil
        return sink.drain()
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
/// `samples` is shared with `drain` (main thread) and is guarded.
final class SampleSink: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
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
        lock.withLock { samples.append(contentsOf: chunk) }
        onLevel(Self.level(of: chunk))
        onSamples?(chunk)
    }

    func drain() -> [Float] {
        lock.withLock {
            let out = samples
            samples = []
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
