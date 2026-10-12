import Foundation

/// Minimal RIFF/WAVE writer for 16-bit PCM mono.
///
/// Phonon-2 resamples everything to 16 kHz mono anyway, so the recorder
/// converts on the audio thread and hands this encoder exactly that. Sending
/// 16-bit samples instead of 32-bit floats halves the upload to the engine.
public enum WAV {
    /// The rate Phonon-2 decodes at. Recording at this rate means the engine
    /// does no resampling work of its own.
    public static let sampleRate = 16_000

    /// Encode mono float samples in [-1, 1] as a 16-bit PCM WAV file.
    /// Values outside that range are clipped, not wrapped.
    public static func encode(samples: [Float], sampleRate: Int = WAV.sampleRate) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(samples.count) * UInt32(blockAlign)

        var data = Data(capacity: 44 + Int(dataSize))
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLE(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))

        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLE(UInt32(16))           // fmt chunk size
        data.appendLE(UInt16(1))            // PCM
        data.appendLE(channels)
        data.appendLE(UInt32(sampleRate))
        data.appendLE(byteRate)
        data.appendLE(blockAlign)
        data.appendLE(bitsPerSample)

        data.append(contentsOf: Array("data".utf8))
        data.appendLE(dataSize)
        for sample in samples {
            data.appendLE(UInt16(bitPattern: pcm16(sample)))
        }
        return data
    }

    /// Duration in seconds of `count` samples at the Phonon-2 rate.
    public static func duration(sampleCount count: Int, sampleRate: Int = WAV.sampleRate) -> Double {
        Double(count) / Double(sampleRate)
    }

    static func pcm16(_ sample: Float) -> Int16 {
        guard sample.isFinite else { return 0 }
        let clipped = min(max(sample, -1), 1)
        return Int16((clipped * Float(Int16.max)).rounded())
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
