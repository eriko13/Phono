import UIKit

/// The strip above the keys, where Apple's keyboard shows its suggestions.
/// It shows three suggestions, or a status line instead.
final class TopBar: UIView {
    var onChoose: (Suggestion) -> Void = { _ in }

    private let status = UILabel()
    private let slots = (0 ..< 3).map { _ in UIButton(type: .custom) }
    private let dividers = (0 ..< 2).map { _ in UIView() }
    private var suggestions: [Suggestion?] = [nil, nil, nil]

    override init(frame: CGRect) {
        super.init(frame: frame)
        status.font = .preferredFont(forTextStyle: .footnote)
        status.textAlignment = .center
        status.numberOfLines = 2
        addSubview(status)
        for (index, slot) in slots.enumerated() {
            slot.titleLabel?.font = .systemFont(ofSize: 17)
            slot.titleLabel?.lineBreakMode = .byTruncatingMiddle
            slot.setTitleColor(.label, for: .normal)
            slot.layer.cornerRadius = 8
            slot.layer.cornerCurve = .continuous
            slot.addAction(UIAction { [weak self] _ in self?.choose(index) }, for: .touchUpInside)
            addSubview(slot)
        }
        for divider in dividers {
            divider.backgroundColor = .separator
            addSubview(divider)
        }
        show(suggestions: [])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        status.frame = bounds.insetBy(dx: 12, dy: 0)
        let width = (bounds.width - 8) / 3
        for (index, slot) in slots.enumerated() {
            slot.frame = CGRect(x: 4 + CGFloat(index) * width, y: 4, width: width, height: bounds.height - 8)
                .insetBy(dx: 2, dy: 0)
        }
        for (index, divider) in dividers.enumerated() {
            let x = 4 + CGFloat(index + 1) * width
            divider.frame = CGRect(x: x - 0.5, y: bounds.height * 0.3, width: 1, height: bounds.height * 0.4)
        }
    }

    func show(status text: String, color: UIColor) {
        status.text = text
        status.textColor = color
        status.isHidden = false
        (slots + dividers).forEach { $0.isHidden = true }
    }

    func show(suggestions: [Suggestion]) {
        self.suggestions = (0 ..< 3).map { $0 < suggestions.count ? suggestions[$0] : nil }
        status.isHidden = true
        for (slot, suggestion) in zip(slots, self.suggestions) {
            slot.isHidden = false
            let title = suggestion.map { $0.isTyped ? "“\($0.text)”" : $0.text }
            slot.setTitle(title, for: .normal)
            slot.backgroundColor = suggestion?.isCorrection == true ? .keyCharacter : .clear
            slot.isEnabled = suggestion != nil
            slot.accessibilityLabel = suggestion?.text
        }
        // As on Apple's keyboard, no line next to the highlighted fix.
        for (index, divider) in dividers.enumerated() {
            let besideFix = [index, index + 1].contains { self.suggestions[$0]?.isCorrection == true }
            divider.isHidden = besideFix
        }
    }

    private func choose(_ index: Int) {
        guard let suggestion = suggestions[index] else { return }
        onChoose(suggestion)
    }
}
