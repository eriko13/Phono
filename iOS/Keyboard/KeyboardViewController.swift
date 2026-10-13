import UIKit

/// The Phono keyboard: a keyboard like Apple's that also types what the
/// Phono app heard. It cannot use the microphone, so the app records, from
/// the Talk button in the status bar, and the text comes back here.
final class KeyboardViewController: UIInputViewController {
    private let keyboard = KeyboardView()
    private var height: NSLayoutConstraint?
    private var lastShiftPress: Date?
    private var lastKey: Key?
    private var state: KeyboardLink.State = .idle
    private var error: String?

    override func loadView() {
        view = ClickingInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        keyboard.onKey = { [weak self] key in self?.perform(key) }
        keyboard.onCursor = { [weak self] offset in
            self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        }
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard)
        let height = view.heightAnchor.constraint(equalToConstant: 260)
        height.priority = .required - 1
        self.height = height
        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])

        KeyboardLink.observe { [weak self] in self?.appChanged() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Text the app sent while another field was active is not for this one.
        _ = KeyboardLink.takeText()
        state = KeyboardLink.state
        error = nil
        keyboard.configuration.page = .letters
        keyboard.configuration.shift = .off
        update()
    }

    override func viewWillLayoutSubviews() {
        height?.constant = traitCollection.verticalSizeClass == .compact ? 196 : 260
        super.viewWillLayoutSubviews()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        update()
    }

    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput)
        update()
    }

    private func appChanged() {
        state = KeyboardLink.state
        error = KeyboardLink.error
        if let text = KeyboardLink.takeText() { insert(text) }
        update()
    }

    private func insert(_ text: String) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let needsSpace = before.last.map { !$0.isWhitespace } ?? false
        textDocumentProxy.insertText(needsSpace ? " " + text : text)
    }

    // MARK: Keys

    private func perform(_ key: Key) {
        let proxy = textDocumentProxy
        var configuration = keyboard.configuration
        switch key {
        case .character(let text):
            let letters = configuration.page == .letters
            proxy.insertText(letters && configuration.shift != .off ? text.uppercased() : text)
            if configuration.shift == .once { configuration.shift = .off }
            // As on Apple's keyboard, an apostrophe goes back to the letters.
            if !letters && text == "'" { configuration.page = .letters }
        case .space:
            // Two spaces after a word end the sentence.
            let before = proxy.documentContextBeforeInput ?? ""
            if lastKey == .space, before.hasSuffix(" "),
               before.dropLast().last.map({ $0.isLetter || $0.isNumber }) == true {
                proxy.deleteBackward()
                proxy.insertText(". ")
            } else {
                proxy.insertText(" ")
            }
            configuration.page = .letters
        case .return:
            proxy.insertText("\n")
        case .delete:
            proxy.deleteBackward()
        case .shift:
            let now = Date()
            let doubleTap = lastShiftPress.map { now.timeIntervalSince($0) < 0.35 } ?? false
            switch configuration.shift {
            case .off: configuration.shift = .once
            case .once: configuration.shift = doubleTap ? .locked : .off
            case .locked: configuration.shift = .off
            }
            lastShiftPress = now
        case .nextKeyboard:
            advanceToNextInputMode()
        case .page(let page):
            configuration.page = page
        }
        keyboard.configuration = configuration
        lastKey = key
        if key != .shift { update() }
    }

    /// Matches the keyboard to the text field and to the app's state.
    private func update() {
        let proxy = textDocumentProxy
        view.overrideUserInterfaceStyle = proxy.keyboardAppearance == .dark ? .dark : .unspecified

        var configuration = keyboard.configuration
        configuration.showsGlobe = needsInputModeSwitchKey
        if configuration.shift != .locked {
            configuration.shift = capitalizes ? .once : .off
        }
        (configuration.returnTitle, configuration.returnIsBlue) = returnKey(proxy.returnKeyType ?? .default)
        configuration.returnEnabled = !(proxy.enablesReturnKeyAutomatically ?? false) || proxy.hasText
        keyboard.configuration = configuration

        if !hasFullAccess {
            show("Allow Full Access to type what you dictate: Settings › Apps › Phono › Keyboards.", .secondaryLabel)
        } else if let error {
            show(error, .systemRed)
        } else {
            switch state {
            case .idle: show("Press Talk at the top of the screen to dictate.", .tertiaryLabel)
            case .recording: show("Listening…", .systemRed)
            case .transcribing: show("Transcribing…", .secondaryLabel)
            }
        }
    }

    private func show(_ status: String, _ color: UIColor) {
        keyboard.bar.show(status: status, color: color)
    }

    /// Whether the next letter starts a sentence or word, as the field asks.
    private var capitalizes: Bool {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            return before.last.map(\.isWhitespace) ?? true
        case .sentences:
            guard let last = before.last else { return true }
            if last.isNewline { return true }
            guard last == " " else { return false }
            guard let end = before.last(where: { $0 != " " }) else { return true }
            return ".!?".contains(end) || end.isNewline
        @unknown default:
            return false
        }
    }

    private func returnKey(_ type: UIReturnKeyType) -> (String, Bool) {
        switch type {
        case .go: ("go", true)
        case .google, .yahoo, .search: ("search", true)
        case .join: ("join", true)
        case .next: ("next", false)
        case .route: ("route", true)
        case .send: ("send", true)
        case .done: ("done", true)
        case .emergencyCall: ("Emergency", true)
        case .continue: ("continue", true)
        default: ("return", false)
        }
    }
}

/// Lets the keys play the keyboard click, when the user has it on.
private final class ClickingInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
