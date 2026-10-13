/// Turns one clip of 16 kHz mono samples into text.
public protocol Transcribing: Sendable {
    func transcribe(_ samples: [Float]) async throws -> String
}
