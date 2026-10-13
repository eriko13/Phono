import Foundation
import PhonoCore

/// One dictation streamed live to a Phonon server over its WebSocket.
///
/// Audio goes out while the shortcut is held, and `onPreview` gets the text
/// heard so far after each partial or final. `finish()` ends the stream and
/// returns the server's whole transcript.
///
/// `send` runs on the audio thread, the receive loop on a background task,
/// and the rest on the main thread, so shared state is behind a lock.
/// URLSession sends messages in the order `send` is called.
final class ServerStream: @unchecked Sendable {
    /// The server only has the last phrase left to decode, which takes well
    /// under a second. Anything slower than this is a network problem.
    private static let finishTimeout: Duration = .seconds(10)

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private let task: URLSessionWebSocketTask
    private let onPreview: @Sendable (String) -> Void
    private let lock = NSLock()
    private var transcript = LiveTranscript()
    /// Set once: the transcript, or why the stream failed.
    private var outcome: Result<String, any Error>?
    private var waiter: CheckedContinuation<String, any Error>?

    init(base: URL, key: String, onPreview: @escaping @Sendable (String) -> Void) {
        var request = URLRequest(url: Server.streamURL(base))
        // A header, not `?api_key=`: the server logs query strings.
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        task = Self.session.webSocketTask(with: request)
        self.onPreview = onPreview
    }

    func start() {
        task.resume()
        task.send(.string(Server.streamStart)) { _ in }
        Task.detached { [self] in await self.receive() }
    }

    /// 16 kHz mono samples, on the audio thread.
    func send(_ samples: [Float]) {
        guard lock.withLock({ outcome == nil }) else { return }
        task.send(.data(Server.pcm16(samples))) { _ in }
    }

    /// End the stream and wait for the whole transcript. Throws if the
    /// stream failed at any point, so the caller can send the clip instead.
    func finish() async throws -> String {
        task.send(.string(Server.streamEnd)) { _ in }
        let timeout = Task.detached { [self] in
            do { try await Task.sleep(for: Self.finishTimeout) } catch { return }
            self.resolve(.failure(ServerStreamError.timedOut))
        }
        defer {
            timeout.cancel()
            close()
        }
        return try await withCheckedThrowingContinuation { continuation in
            let outcome: Result<String, any Error>? = lock.withLock {
                if self.outcome == nil { waiter = continuation }
                return self.outcome
            }
            if let outcome { continuation.resume(with: outcome) }
        }
    }

    /// Drop the stream, for example when the recording is thrown away.
    func close() {
        task.cancel(with: .normalClosure, reason: nil)
        resolve(.failure(CancellationError()))
    }

    private func receive() async {
        do {
            while true {
                let data: Data
                switch try await task.receive() {
                case .string(let text): data = Data(text.utf8)
                case .data(let bytes): data = bytes
                @unknown default: continue
                }
                guard let event = StreamEvent(json: data) else { continue }
                switch event {
                case .done(let text):
                    return resolve(.success(text))
                case .error(let message):
                    return resolve(.failure(ServerStreamError.server(message)))
                case .partial, .final:
                    let text = lock.withLock {
                        transcript.apply(event)
                        return transcript.text
                    }
                    if !text.isEmpty { onPreview(text) }
                }
            }
        } catch {
            resolve(.failure(error))
        }
    }

    /// The first outcome wins; later ones (a close after `done`) are dropped.
    private func resolve(_ result: Result<String, any Error>) {
        let waiter: CheckedContinuation<String, any Error>? = lock.withLock {
            guard outcome == nil else { return nil }
            outcome = result
            defer { self.waiter = nil }
            return self.waiter
        }
        waiter?.resume(with: result)
    }
}

enum ServerStreamError: Error, CustomStringConvertible {
    case server(String)
    case timedOut

    var description: String {
        switch self {
        case .server(let message): return "the server said: \(message)"
        case .timedOut: return "no transcript from the stream"
        }
    }
}
