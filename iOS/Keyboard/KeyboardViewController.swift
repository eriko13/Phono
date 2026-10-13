import SwiftUI
import UIKit

/// The Phono keyboard. It cannot use the microphone, so the app records:
/// the first tap opens the app, which turns the microphone on. After that,
/// each tap starts or stops a clip in the app, and the text comes back here.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    /// Set while a signal to the app waits for its answer.
    private var waitingForApp: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        model.onMic = { [weak self] in self?.micTapped() }
        model.onNextKeyboard = { [weak self] in self?.advanceToNextInputMode() }
        model.onKey = { [weak self] key in self?.type(key) }

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.heightAnchor.constraint(equalToConstant: 220),
        ])
        host.didMove(toParent: self)

        KeyboardLink.observe(.changed) { [weak self] in self?.appChanged() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Text the app sent while another field was active is not for this one.
        _ = KeyboardLink.takeText()
        model.hasFullAccess = hasFullAccess
        model.showsNextKeyboard = needsInputModeSwitchKey
        model.state = .off
        model.error = nil
        KeyboardLink.post(.ping)
    }

    private func appChanged() {
        waitingForApp?.cancel()
        model.state = KeyboardLink.state
        model.error = KeyboardLink.error
        if let text = KeyboardLink.takeText() { insert(text) }
    }

    private func micTapped() {
        guard hasFullAccess else { return }
        guard model.state != .off else {
            openApp()
            return
        }
        KeyboardLink.post(.toggle)
        // The app answers at once if it is still there. If not, iOS has ended
        // it, so open it again.
        waitingForApp = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.model.state = .off
            self.openApp()
        }
    }

    private func insert(_ text: String) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let needsSpace = before.last.map { !$0.isWhitespace } ?? false
        textDocumentProxy.insertText(needsSpace ? " " + text : text)
    }

    private func type(_ key: KeyboardModel.Key) {
        switch key {
        case .space: textDocumentProxy.insertText(" ")
        case .return: textDocumentProxy.insertText("\n")
        case .delete: textDocumentProxy.deleteBackward()
        }
    }

    /// Extensions cannot call `UIApplication.shared`, but the application is
    /// still in the responder chain.
    private func openApp() {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(KeyboardLink.openURL, options: [:], completionHandler: nil)
                return
            }
            responder = current.next
        }
    }
}
