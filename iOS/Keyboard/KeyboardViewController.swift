import PhonoCore
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
    /// The dictated text last typed, so that each is typed once.
    private var typedTextID: UUID?
    private let suggester = Suggester()
    /// The last fix space made, so that delete right after can undo it.
    private var lastCorrection: (typed: String, fixed: String, end: String)?

    override func loadView() {
        view = ClickingInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        keyboard.onKey = { [weak self] key in self?.perform(key) }
        keyboard.onCursor = { [weak self] offset in
            self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        }
        keyboard.bar.onChoose = { [weak self] suggestion in self?.choose(suggestion) }
        requestSupplementaryLexicon { [weak self] lexicon in self?.suggester.use(lexicon) }
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
        let message = KeyboardLink.read()
        typedTextID = message.textID
        state = message.state
        error = nil
        keyboard.configuration.page = .letters
        keyboard.configuration.shift = .off
        update()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        suggester.save()
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
        let previous = state
        let message = KeyboardLink.read()
        state = message.state
        // A Talk press has no feel of its own, and iOS does not let the app
        // play haptics from the background, so the keyboard does.
        if state == .recording, previous != .recording {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        } else if previous == .recording, state != .recording {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
        }
        error = message.error
        if let text = message.text, message.textID != typedTextID {
            typedTextID = message.textID
            insert(text)
        }
        update()
    }

    private func insert(_ text: String) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        textDocumentProxy.insertText(Typing.needsSpace(before: before) ? " " + text : text)
    }

    // MARK: Keys

    private func perform(_ key: Key) {
        let proxy = textDocumentProxy
        var configuration = keyboard.configuration
        let correction = lastCorrection
        lastCorrection = nil
        switch key {
        case .character(let text):
            if Self.wordEnds.contains(text) { endWord(with: text) }
            let letters = configuration.page == .letters
            proxy.insertText(letters && configuration.shift != .off ? text.uppercased() : text)
            if configuration.shift == .once { configuration.shift = .off }
            // As on Apple's keyboard, an apostrophe goes back to the letters.
            if !letters && text == "'" { configuration.page = .letters }
        case .space:
            endWord(with: " ")
            // Two spaces after a word end the sentence.
            let before = proxy.documentContextBeforeInput ?? ""
            if Typing.spaceEndsSentence(after: before, lastKeyWasSpace: lastKey == .space) {
                proxy.deleteBackward()
                proxy.insertText(". ")
            } else {
                proxy.insertText(" ")
            }
            configuration.page = .letters
        case .return:
            proxy.insertText("\n")
        case .delete:
            let before = proxy.documentContextBeforeInput ?? ""
            if let correction, before.hasSuffix(correction.fixed + correction.end) {
                // Undo the fix: back to what was typed, and keep it.
                for _ in 0 ..< (correction.fixed + correction.end).count { proxy.deleteBackward() }
                proxy.insertText(correction.typed)
                suggester.keep(correction.typed)
            } else {
                proxy.deleteBackward()
            }
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

    /// Characters that end a word, and so apply the fix the bar shows.
    private static let wordEnds: Set<String> = [".", ",", "?", "!", ";", ":"]

    /// Before `end` is typed: puts the fix in place of the word, and learns
    /// which word followed which.
    private func endWord(with end: String) {
        let proxy = textDocumentProxy
        let before = proxy.documentContextBeforeInput ?? ""
        let word = Typing.currentWord(before: before)
        guard !word.isEmpty else { return }
        var final = word
        if autocorrects, let fixed = suggester.correction(for: word) {
            for _ in 0 ..< word.count { proxy.deleteBackward() }
            proxy.insertText(fixed)
            lastCorrection = (word, fixed, end)
            final = fixed
        }
        suggester.learn(final, before: String(before.dropLast(word.count)))
    }

    private func choose(_ suggestion: Suggestion) {
        let proxy = textDocumentProxy
        let before = proxy.documentContextBeforeInput ?? ""
        let word = Typing.currentWord(before: before)
        for _ in 0 ..< word.count { proxy.deleteBackward() }
        proxy.insertText(suggestion.text + " ")
        if suggestion.isTyped { suggester.keep(suggestion.text) }
        suggester.learn(suggestion.text, before: String(before.dropLast(word.count)))
        lastKey = nil
        lastCorrection = nil
        keyboard.configuration.page = .letters
        update()
    }

    /// The field wants fixes: not in addresses, and not where the app turned
    /// them off.
    private var autocorrects: Bool {
        let proxy = textDocumentProxy
        let type = proxy.keyboardType ?? .default
        return proxy.autocorrectionType != .no && ![.URL, .emailAddress, .webSearch].contains(type)
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

        let suggestions = autocorrects
            ? suggester.suggestions(
                before: proxy.documentContextBeforeInput ?? "",
                after: proxy.documentContextAfterInput ?? "",
                capitalizes: capitalizes
            )
            : []
        if let error {
            show(error, .systemRed)
        } else if state == .recording {
            show("Listening…", .systemRed)
        } else if state == .transcribing {
            show("Transcribing…", .secondaryLabel)
        } else if !suggestions.isEmpty {
            keyboard.bar.show(suggestions: suggestions)
        } else if !hasFullAccess {
            show("Allow Full Access to type what you dictate: Settings › Apps › Phono › Keyboards.", .secondaryLabel)
        } else {
            show("Press Talk at the top of the screen to dictate.", .tertiaryLabel)
        }
    }

    private func show(_ status: String, _ color: UIColor) {
        keyboard.bar.show(status: status, color: color)
    }

    /// Whether the next letter starts a sentence or word, as the field asks.
    private var capitalizes: Bool {
        let mode: Typing.Capitalization = switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none: .none
        case .words: .words
        case .sentences: .sentences
        case .allCharacters: .allCharacters
        @unknown default: .none
        }
        return Typing.capitalizes(after: textDocumentProxy.documentContextBeforeInput ?? "", mode)
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
