import Foundation

/// How the app and the keyboard talk to each other.
///
/// A keyboard extension cannot use the microphone, so the app records, from
/// its Talk button, and the keyboard types the text. The state and the text go
/// through the defaults of the shared App Group, and a Darwin notification,
/// which carries no data, says that they changed.
enum KeyboardLink {
    enum State: String {
        case idle
        case recording
        case transcribing
    }

    private static let group = "group.io.github.eriko13.phono"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: group) }
    private static let changed = "io.github.eriko13.phono.changed"

    // MARK: App side

    static func publish(_ state: State, error: String?) {
        defaults?.set(state.rawValue, forKey: "state")
        defaults?.set(error, forKey: "error")
        post()
    }

    static func send(_ text: String) {
        defaults?.set(text, forKey: "text")
        post()
    }

    // MARK: Keyboard side

    /// What the app last published.
    struct Message {
        var state: State = .idle
        var error: String?
    }

    static func read() -> Message {
        Message(
            state: defaults?.string(forKey: "state").flatMap(State.init) ?? .idle,
            error: defaults?.string(forKey: "error")
        )
    }

    /// The text the app sent, once.
    static func takeText() -> String? {
        let text = defaults?.string(forKey: "text")
        if text != nil { defaults?.removeObject(forKey: "text") }
        return text
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
