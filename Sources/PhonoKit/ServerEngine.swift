import Foundation
import PhonoCore

/// Phonon-2 on another machine: each clip goes to a Phonon server as a WAV
/// file, and the text comes back.
public struct ServerEngine: Transcribing {
    public let base: URL
    public let key: String

    public init(base: URL, key: String) {
        self.base = base
        self.key = key
    }

    /// Clips are at most a minute or two of audio, and the server answers in
    /// well under a second. Anything slower than this is a network problem.
    private static let timeout: TimeInterval = 15

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// Throws unless the server transcribes half a second of silence. That
    /// checks the key too: `/health` answers without one, and the
    /// phonon-cuda image has no `/v1/models`.
    public func checkConnection() async throws {
        _ = try await transcribe([Float](repeating: 0, count: Int(Model.sampleRate) / 2), timeout: 5)
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        try await transcribe(samples, timeout: Self.timeout)
    }

    private func transcribe(_ samples: [Float], timeout: TimeInterval) async throws -> String {
        let boundary = "phono-\(UUID().uuidString)"
        var request = URLRequest(url: Server.url(base, Server.transcriptionsPath))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Server.form(wav: Server.wav(samples), boundary: boundary)
        let data = try await send(request)
        guard let text = Server.text(fromReply: data) else { throw ServerError.unreadableReply }
        return text
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ServerError.status(status, String(decoding: data.prefix(200), as: UTF8.self))
        }
        return data
    }
}

public enum ServerError: Error, CustomStringConvertible, LocalizedError {
    case noServer
    case status(Int, String)
    case unreadableReply

    public var description: String {
        switch self {
        case .noServer: return "no server set — run `phono server <url> <key>`"
        case .status(401, _): return "the server rejected the API key"
        case .status(let code, let body): return "HTTP \(code) \(body)"
        case .unreadableReply: return "the server's reply had no text"
        }
    }

    public var errorDescription: String? { description }
}
