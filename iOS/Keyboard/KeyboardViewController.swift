import SwiftUI
import UIKit

/// The Phono keyboard. It cannot use the microphone, so the app records,
/// from the Talk button in the status bar, and the text comes back here.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()

    override func viewDidLoad() {
        super.viewDidLoad()
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
            host.view.heightAnchor.constraint(equalToConstant: 140),
        ])
        host.didMove(toParent: self)

        KeyboardLink.observe { [weak self] in self?.appChanged() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Text the app sent while another field was active is not for this one.
        _ = KeyboardLink.takeText()
        model.hasFullAccess = hasFullAccess
        model.showsNextKeyboard = needsInputModeSwitchKey
        model.state = KeyboardLink.state
        model.error = nil
    }

    private func appChanged() {
        model.state = KeyboardLink.state
        model.error = KeyboardLink.error
        if let text = KeyboardLink.takeText() { insert(text) }
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
}
