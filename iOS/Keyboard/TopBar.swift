import UIKit

/// The strip above the keys, where Apple's keyboard shows its suggestions.
final class TopBar: UIView {
    private let status = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        status.font = .preferredFont(forTextStyle: .footnote)
        status.textAlignment = .center
        status.numberOfLines = 2
        addSubview(status)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        status.frame = bounds.insetBy(dx: 12, dy: 0)
    }

    func show(status text: String, color: UIColor) {
        status.text = text
        status.textColor = color
    }
}
