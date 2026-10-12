import Foundation
import XCTest
@testable import PhonoCore

final class MultipartTests: XCTestCase {
    func testBodyLayout() {
        var form = MultipartForm(boundary: "B")
        form.addField(name: "response_format", value: "json")
        form.addFile(name: "file", filename: "a.wav", contentType: "audio/wav", data: Data("XY".utf8))
        let body = String(decoding: form.finalized(), as: UTF8.self)
        XCTAssertEqual(body, """
            --B\r
            Content-Disposition: form-data; name="response_format"\r
            \r
            json\r
            --B\r
            Content-Disposition: form-data; name="file"; filename="a.wav"\r
            Content-Type: audio/wav\r
            \r
            XY\r
            --B--\r

            """)
        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=B")
    }
}

final class TranscriptionClientTests: XCTestCase {
    let client = TranscriptionClient(baseURL: TranscriptionClient.loopback(port: 8178))

    func testLoopbackURL() {
        XCTAssertEqual(client.baseURL.absoluteString, "http://127.0.0.1:8178")
    }

    func testTranscriptionRequest() throws {
        let request = client.transcriptionRequest(audio: Data([1, 2]), hotwords: ["Ada", "Quillon"])
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8178/v1/audio/transcriptions")
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"hotwords\"\r\n\r\nAda, Quillon\r\n"))
        XCTAssertTrue(body.contains("filename=\"dictation.wav\""))
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))
    }

    func testFileTypeFollowsExtension() throws {
        let request = client.transcriptionRequest(audio: Data(), filename: "talk.FLAC", hotwords: [])
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("filename=\"talk.FLAC\"\r\nContent-Type: audio/flac"))
    }

    func testNoHotwordsFieldWhenEmpty() throws {
        let request = client.transcriptionRequest(audio: Data(), hotwords: [])
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertFalse(body.contains("hotwords"))
    }

    func testHealthRequest() {
        XCTAssertEqual(client.healthRequest(timeout: 1).url?.absoluteString, "http://127.0.0.1:8178/health")
    }

    func testParseSuccess() throws {
        let text = try TranscriptionClient.parseTranscription(
            data: Data(#"{"text": "The transcript."}"#.utf8), status: 200)
        XCTAssertEqual(text, "The transcript.")
    }

    func testParseBadBody() {
        XCTAssertThrowsError(try TranscriptionClient.parseTranscription(data: Data("nope".utf8), status: 200)) {
            XCTAssertEqual($0 as? TranscriptionError, .badResponse)
        }
    }

    func testParseErrorShapes() {
        let cases: [(String, String)] = [
            (#"{"error": {"message": "too big"}}"#, "too big"),
            (#"{"detail": "Not Found"}"#, "Not Found"),
            ("plain failure", "plain failure"),
            ("", "no message"),
        ]
        for (body, message) in cases {
            XCTAssertThrowsError(try TranscriptionClient.parseTranscription(data: Data(body.utf8), status: 500)) {
                XCTAssertEqual($0 as? TranscriptionError, .server(status: 500, message: message))
            }
        }
    }
}

final class EngineTests: XCTestCase {
    let home = URL(fileURLWithPath: "/Users/me")

    func testCandidatesOrder() {
        let paths = Engine.candidates(home: home, override: "/x/fermion")
        XCTAssertEqual(paths.first, "/x/fermion")
        XCTAssertEqual(paths[1], "/Users/me/Library/Application Support/Phono/engine/.venv/bin/fermion")
    }

    func testLocatePicksFirstExecutable() {
        let found = Engine.locate(home: home, override: nil) { $0 == "/opt/homebrew/bin/fermion" }
        XCTAssertEqual(found, "/opt/homebrew/bin/fermion")
        XCTAssertNil(Engine.locate(home: home, override: nil) { _ in false })
    }

    func testServeArgumentsBindLoopback() {
        XCTAssertEqual(Engine.serveArguments(port: 9000),
                       ["serve", "phonon-2", "--host", "127.0.0.1", "--port", "9000"])
    }
}
