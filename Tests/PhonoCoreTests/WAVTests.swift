import Foundation
import XCTest
@testable import PhonoCore

final class WAVTests: XCTestCase {
    func testHeaderDescribes16kMono16Bit() {
        let wav = WAV.encode(samples: [0, 0.5, -0.5, 1])
        XCTAssertEqual(wav.count, 44 + 4 * 2)
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(readLE(UInt32.self, wav, 4), 36 + 8)      // RIFF size
        XCTAssertEqual(readLE(UInt16.self, wav, 20), 1)          // PCM
        XCTAssertEqual(readLE(UInt16.self, wav, 22), 1)          // mono
        XCTAssertEqual(readLE(UInt32.self, wav, 24), 16_000)     // sample rate
        XCTAssertEqual(readLE(UInt32.self, wav, 28), 32_000)     // byte rate
        XCTAssertEqual(readLE(UInt16.self, wav, 34), 16)         // bits
        XCTAssertEqual(readLE(UInt32.self, wav, 40), 8)          // data size
    }

    func testSamplesAreClippedNotWrapped() {
        XCTAssertEqual(WAV.pcm16(2), Int16.max)
        XCTAssertEqual(WAV.pcm16(-2), -Int16.max)
        XCTAssertEqual(WAV.pcm16(.nan), 0)
        XCTAssertEqual(WAV.pcm16(0), 0)
    }

    func testDuration() {
        XCTAssertEqual(WAV.duration(sampleCount: 8_000), 0.5)
    }

    private func readLE<T: FixedWidthInteger>(_: T.Type, _ data: Data, _ offset: Int) -> T {
        var value: T = 0
        for i in 0..<MemoryLayout<T>.size {
            value |= T(data[data.startIndex + offset + i]) << (8 * i)
        }
        return value
    }
}
