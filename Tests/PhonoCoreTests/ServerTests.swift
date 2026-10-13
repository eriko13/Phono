import Foundation
import XCTest
@testable import PhonoCore

final class ServerTests: XCTestCase {
    func testBaseURL() {
        XCTAssertEqual(Server.baseURL("overmn:8000")?.absoluteString, "http://overmn:8000")
        XCTAssertEqual(Server.baseURL(" http://overmn:8000/ ")?.absoluteString, "http://overmn:8000")
        XCTAssertEqual(Server.baseURL("https://box.example.ts.net")?.absoluteString, "https://box.example.ts.net")
        XCTAssertNil(Server.baseURL(""))
        XCTAssertNil(Server.baseURL("ftp://overmn"))
        XCTAssertNil(Server.baseURL("http://"))
    }

    func testURL() {
        let base = URL(string: "http://overmn:8000")!
        XCTAssertEqual(Server.url(base, Server.transcriptionsPath).absoluteString,
                       "http://overmn:8000/v1/audio/transcriptions")
    }

    func testStreamURL() {
        XCTAssertEqual(Server.streamURL(URL(string: "http://overmn:8000")!).absoluteString,
                       "ws://overmn:8000/v1/audio/stream")
        XCTAssertEqual(Server.streamURL(URL(string: "https://box.example.ts.net")!).absoluteString,
                       "wss://box.example.ts.net/v1/audio/stream")
    }

    func testPCM16() {
        let pcm = Server.pcm16([0, 1, -1, 2])
        XCTAssertEqual(pcm.count, 8)
        XCTAssertEqual(Server.wav([0, 1, -1, 2]).suffix(8), pcm)
    }

    func testStreamEvents() {
        func event(_ json: String) -> StreamEvent? { StreamEvent(json: Data(json.utf8)) }
        XCTAssertEqual(event(#"{"type": "partial", "text": "The New"}"#), .partial("The New"))
        XCTAssertEqual(event(#"{"type": "final", "text": "Hi.", "segment": 1}"#), .final("Hi."))
        XCTAssertEqual(event(#"{"type": "done", "text": "Hi."}"#), .done("Hi."))
        XCTAssertEqual(event(#"{"type": "error", "message": "engine busy"}"#), .error("engine busy"))
        XCTAssertNil(event(#"{"type": "ping"}"#))
        XCTAssertNil(event("not json"))
    }

    func testLiveTranscript() {
        var live = LiveTranscript()
        XCTAssertEqual(live.text, "")
        live.apply(.partial("nineteen sixty one"))
        live.apply(.partial("nineteen sixty nine."))
        XCTAssertEqual(live.text, "nineteen sixty nine.")
        live.apply(.final("Nineteen sixty nine."))
        XCTAssertEqual(live.text, "Nineteen sixty nine.")
        live.apply(.partial("Men walk"))
        XCTAssertEqual(live.text, "Nineteen sixty nine. Men walk")
        live.apply(.done("ignored"))
        XCTAssertEqual(live.finals, ["Nineteen sixty nine."])
    }

    func testWAV() {
        let wav = Server.wav([0, 1, -1, 2], sampleRate: 16_000)
        XCTAssertEqual(wav.count, 44 + 8)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<16], as: UTF8.self), "WAVEfmt ")
        XCTAssertEqual(String(decoding: wav[36..<40], as: UTF8.self), "data")

        func int16(at offset: Int) -> Int16 {
            Int16(littleEndian: wav[offset..<offset + 2].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) })
        }
        func uint32(at offset: Int) -> UInt32 {
            UInt32(littleEndian: wav[offset..<offset + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        }
        XCTAssertEqual(uint32(at: 24), 16_000)
        XCTAssertEqual(uint32(at: 40), 8)
        // Out-of-range samples clip instead of wrapping.
        XCTAssertEqual([44, 46, 48, 50].map(int16), [0, .max, -.max, .max])
    }

    func testForm() {
        let body = String(decoding: Server.form(wav: Data("AUDIO".utf8), boundary: "B"), as: UTF8.self)
        XCTAssertTrue(body.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n"))
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"clip.wav\"\r\nContent-Type: audio/wav\r\n\r\nAUDIO\r\n"))
        XCTAssertTrue(body.hasSuffix("\r\n--B--\r\n"))
    }

    func testReply() {
        XCTAssertEqual(Server.text(fromReply: Data(#"{"text": "Hello there."}"#.utf8)), "Hello there.")
        XCTAssertNil(Server.text(fromReply: Data(#"{"error": "nope"}"#.utf8)))
        XCTAssertNil(Server.text(fromReply: Data("not json".utf8)))
    }
}
