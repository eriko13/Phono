import Foundation

/// How the keyboard and the app talk to each other.
///
/// A keyboard extension cannot use the microphone, so the app records and
/// transcribes, and the keyboard types the text. Signals are Darwin
/// notifications, which carry no data. The state and the text go through the
/// defaults of the shared App Group.
enum KeyboardLink {
    /// The keyboard opens this to start a keyboard session in the app.
    static let openURL = URL(string: "phono://dictate")!

    enum Signal: String {
        /// Keyboard to app: start or stop a clip.
        case toggle
        /// Keyboard to app: answer with `changed` if you are there.
        case ping
        /// App to keyboard: the state or the text changed.
        case changed
    }

    enum State: String {
        /// No keyboard session. The app's microphone is off.
        case off
        case ready
        case recording
        case transcribing
    }

    private static let group = "group.io.github.eriko13.phono"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    // MARK: App side

    static func publish(_ state: State, error: String?) {
        defaults?.set(state.rawValue, forKey: "state")
        defaults?.set(error, forKey: "error")
        post(.changed)
    }

    static func send(_ text: String) {
        defaults?.set(text, forKey: "text")
        post(.changed)
    }

    // MARK: Keyboard side

    static var state: State {
        defaults?.string(forKey: "state").flatMap(State.init) ?? .off
    }

    static var error: String? {
        defaults?.string(forKey: "error")
    }

    /// The text the app sent, once.
    static func takeText() -> String? {
        let text = defaults?.string(forKey: "text")
        if text != nil { defaults?.removeObject(forKey: "text") }
        return text
    }

    // MARK: Signals

    static func post(_ signal: Signal) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name(signal) as CFString), nil, nil, true
        )
    }

    /// Calls `handler` on the main thread each time `signal` is posted, by
    /// any process. A second call for the same signal replaces the handler.
    @MainActor
    static func observe(_ signal: Signal, _ handler: @escaping @MainActor () -> Void) {
        let name = name(signal)
        if handlers[name] == nil {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), nil,
                { _, _, name, _, _ in
                    guard let name = name.map({ $0.rawValue as String }) else { return }
                    Task { @MainActor in handlers[name]?() }
                },
                name as CFString, nil, .deliverImmediately
            )
        }
        handlers[name] = handler
    }

    private static func name(_ signal: Signal) -> String {
        "io.github.eriko13.phono.\(signal.rawValue)"
    }
}

@MainActor private var handlers: [String: @MainActor () -> Void] = [:]
