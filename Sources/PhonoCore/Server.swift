import Foundation

/// Where speech becomes text.
public enum Engine: String, CaseIterable, Sendable {
    /// Phonon-2 on this Mac's Neural Engine.
    case local
    /// A Phonon server, such as `fermion serve phonon-2` or the phonon-cuda
    /// Docker image, reached over the network.
    case server

    public var title: String {
        switch self {
        case .local: return "This Mac"
        case .server: return "Server"
        }
    }
}

/// The parts of talking to a Phonon server that need no networking: URLs,
/// the request body, and the reply. The server speaks OpenAI's audio API,
/// plus a WebSocket stream for live text.
public enum Server {
    public static let transcriptionsPath = "/v1/audio/transcriptions"
    public static let streamPath = "/v1/audio/stream"

    /// The first message on a stream: 16 kHz mono 16-bit PCM follows.
    public static let streamStart = #"{"sample_rate": 16000, "format": "pcm_s16le"}"#
    /// The last message: the server finishes the open phrase and sends `done`.
    public static let streamEnd = #"{"type": "end"}"#

    /// `overmn:8000`, `http://overmn:8000`, and `http://overmn:8000/` all
    /// name the same server. Without a scheme, http is assumed.
    public static func baseURL(_ text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    public static func url(_ base: URL, _ path: String) -> URL {
        URL(string: base.absoluteString + path)!
    }

    /// The stream lives on the same host and port: http becomes ws, and
    /// https becomes wss.
    public static func streamURL(_ base: URL) -> URL {
        var components = URLComponents(url: url(base, streamPath), resolvingAgainstBaseURL: false)!
        components.scheme = base.scheme?.lowercased() == "https" ? "wss" : "ws"
        return components.url!
    }

    /// 16-bit little-endian PCM, the WAV's data and the stream's frames.
    public static func pcm16(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let value = Int16((min(max(sample, -1), 1) * Float(Int16.max)).rounded())
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// 16-bit PCM WAV, mono. Half the size of float samples, and every
    /// server reads it.
    public static func wav(_ samples: [Float], sampleRate: Int = Int(Model.sampleRate)) -> Data {
        let dataSize = UInt32(samples.count * 2)
        var data = Data(capacity: 44 + Int(dataSize))
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))                  // fmt chunk size
        append(UInt16(1))                   // PCM
        append(UInt16(1))                   // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))      // bytes per second
        append(UInt16(2))                   // bytes per frame
        append(UInt16(16))                  // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)
        data.append(pcm16(samples))
        return data
    }

    /// A multipart form with the audio in the `file` field.
    public static func form(wav: Data, boundary: String) -> Data {
        var body = Data()
        body.append(Data("""
            --\(boundary)\r
            Content-Disposition: form-data; name="response_format"\r
            \r
            json\r
            --\(boundary)\r
            Content-Disposition: form-data; name="file"; filename="clip.wav"\r
            Content-Type: audio/wav\r
            \r

            """.utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    /// `{"text": "…"}` → the text.
    public static func text(fromReply data: Data) -> String? {
        let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return reply?["text"] as? String
    }
}

/// One message from the server on a stream.
public enum StreamEvent: Equatable, Sendable {
    /// The phrase being spoken, decoded again from its start. It replaces
    /// the previous partial, and may change words that one had.
    case partial(String)
    /// A phrase the server closed after a pause. It will not change.
    case final(String)
    /// The whole transcript, after the client's `end`. The last message.
    case done(String)
    /// The server refused or failed. It closes the stream after this.
    case error(String)

    /// `{"type": "partial", "text": "…"}` and friends. Unknown types: nil.
    public init?(json data: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = message["type"] as? String
        else { return nil }
        let text = message["text"] as? String ?? ""
        switch type {
        case "partial": self = .partial(text)
        case "final": self = .final(text)
        case "done": self = .done(text)
        case "error": self = .error(message["message"] as? String ?? "unknown error")
        default: return nil
        }
    }
}

/// What a stream has heard so far, for the preview: closed phrases, then
/// the phrase still being spoken.
public struct LiveTranscript: Equatable, Sendable {
    public private(set) var finals: [String] = []
    public private(set) var partial = ""

    public init() {}

    public mutating func apply(_ event: StreamEvent) {
        switch event {
        case .partial(let text):
            partial = text
        case .final(let text):
            finals.append(text)
            partial = ""
        case .done, .error:
            break
        }
    }

    public var text: String {
        (finals + [partial]).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
