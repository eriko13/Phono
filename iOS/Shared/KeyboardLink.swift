import Foundation

/// How the app and the keyboard talk to each other.
///
/// A keyboard extension cannot use the microphone, so the app records, from
/// its Talk button, and the keyboard types the text. The app writes the state
/// and the text to one file in the shared App Group container, then posts a
/// Darwin notification, which carries no data, to say that it changed.
enum KeyboardLink {
    enum State: String, Codable {
        case idle
        case recording
        case transcribing
    }

    /// What the app last published.
    struct Message: Codable {
        var state: State = .idle
        var error: String?
        var text: String?
        /// New for each text, so the keyboard types each text once.
        var textID: UUID?
    }

    private static let group = "group.io.github.eriko13.phono"
    private static let changed = "io.github.eriko13.phono.changed"
    /// A file, not shared defaults: the file is written in full before the
    /// notification goes out, but defaults reach the other process a moment
    /// later, so the keyboard could read them before the text arrives.
    private static let file = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: group)?
        .appendingPathComponent("keyboard-link.json")

    // MARK: App side

    @MainActor private static var current = Message()

    @MainActor
    static func publish(_ state: State, error: String?) {
        current.state = state
        current.error = error
        write()
    }

    @MainActor
    static func send(_ text: String) {
        current.text = text
        current.textID = UUID()
        write()
    }

    @MainActor
    private static func write() {
        guard let file, let data = try? JSONEncoder().encode(current) else { return }
        try? data.write(to: file, options: .atomic)
        post()
    }

    // MARK: Keyboard side

    static func read() -> Message {
        file.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Message.self, from: $0) } ?? Message()
    }

    /// Calls `handler` on the main thread each time the app publishes. A
    /// second call replaces the handler.
    @MainActor
    static func observe(_ handler: @escaping @MainActor () -> Void) {
        if changeHandler == nil {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), nil,
                { _, _, _, _, _ in
                    Task { @MainActor in changeHandler?() }
                },
                changed as CFString, nil, .deliverImmediately
            )
        }
        changeHandler = handler
    }

    private static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(changed as CFString), nil, nil, true
        )
    }
}

@MainActor private var changeHandler: (@MainActor () -> Void)?
