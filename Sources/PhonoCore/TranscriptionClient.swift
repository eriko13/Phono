import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TranscriptionError: Error, Equatable, CustomStringConvertible {
    /// Nothing answered on the engine's port.
    case unreachable(String)
    /// The engine answered with a non-2xx status.
    case server(status: Int, message: String)
    /// The engine answered 2xx, but not with the JSON it documents.
    case badResponse

    public var description: String {
        switch self {
        case .unreachable(let detail):
            return "engine not reachable (\(detail))"
        case .server(let status, let message):
            return "engine error \(status): \(message)"
        case .badResponse:
            return "engine returned an unexpected response"
        }
    }
}

/// Talks to a local `fermion serve phonon-2` process.
///
/// The only network traffic Phono makes goes through this type, and it only
/// ever targets the loopback address in `baseURL`.
public struct TranscriptionClient: Sendable {
    public let baseURL: URL
    public let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// `http://127.0.0.1:<port>`. Loopback only: the engine never needs to
    /// be reachable from another machine.
    public static func loopback(port: Int) -> URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    // MARK: - Requests

    public func healthRequest(timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = timeout
        return request
    }

    /// `filename` tells the engine how to decode `audio`; it reads wav, flac,
    /// ogg, and aiff.
    public func transcriptionRequest(
        audio: Data, filename: String = "dictation.wav", hotwords: [String]
    ) -> URLRequest {
        var form = MultipartForm()
        form.addField(name: "response_format", value: "json")
        if !hotwords.isEmpty {
            form.addField(name: "hotwords", value: hotwords.joined(separator: ", "))
        }
        form.addFile(name: "file", filename: filename, contentType: Self.contentType(for: filename), data: audio)

        var request = URLRequest(
            url: baseURL.appendingPathComponent("v1/audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()
        // Phonon-2 runs at well over 100x realtime once loaded. A long timeout
        // only matters for the first request after a cold engine start.
        request.timeoutInterval = 120
        return request
    }

    // MARK: - Calls

    /// True when `/health` answers 200 within `timeout`.
    public func isHealthy(timeout: TimeInterval = 1) async -> Bool {
        guard let (_, response) = try? await session.data(for: healthRequest(timeout: timeout)),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    public func transcribe(
        audio: Data, filename: String = "dictation.wav", hotwords: [String] = []
    ) async throws -> String {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(
                for: transcriptionRequest(audio: audio, filename: filename, hotwords: hotwords))
        } catch {
            throw TranscriptionError.unreachable(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try Self.parseTranscription(data: data, status: status)
    }

    static func contentType(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        case "ogg": return "audio/ogg"
        case "aif", "aiff": return "audio/aiff"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Parsing

    /// Pull `text` out of `{"text": "..."}`, or turn an error body into a
    /// readable message.
    public static func parseTranscription(data: Data, status: Int) throws -> String {
        guard (200..<300).contains(status) else {
            throw TranscriptionError.server(status: status, message: errorMessage(from: data))
        }
        struct Body: Decodable { let text: String }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            throw TranscriptionError.badResponse
        }
        return body.text
    }

    /// The OpenAI-style `{"error": {"message": …}}`, FastAPI's
    /// `{"detail": …}`, or the body as plain text.
    static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            if let detail = object["detail"] as? String { return detail }
        }
        let text = String(decoding: data.prefix(300), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "no message" : text
    }
}

/// A `multipart/form-data` body, the shape the engine's OpenAI-compatible
/// `/v1/audio/transcriptions` route expects.
struct MultipartForm: Sendable {
    let boundary: String
    private var body = Data()

    init(boundary: String = "phono-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    mutating func addField(name: String, value: String) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data(value.utf8))
        body.append(Data("\r\n".utf8))
    }

    mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    /// The complete body, closing boundary included.
    func finalized() -> Data {
        var out = body
        out.append(Data("--\(boundary)--\r\n".utf8))
        return out
    }
}
