import AppKit

/// A small pill near the bottom of the screen: a live level meter while
/// recording (with the words heard so far, when a server streams them), a
/// spinner while transcribing, or a short message.
///
/// It is a non-activating panel that ignores the mouse, so it never takes
/// focus from the app the text is going into.
@MainActor
final class HUD {
    private let panel: NSPanel
    private let meter = LevelMeterView()
    private let spinner = NSProgressIndicator()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let stack: NSStackView
    private var hideTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 20
        background.layer?.masksToBounds = true

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        icon.contentTintColor = .secondaryLabelColor

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail

        stack = NSStackView(views: [meter, spinner, icon, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 18)
        stack.alignment = .centerY

        panel.contentView = background
        background.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            meter.widthAnchor.constraint(equalToConstant: LevelMeterView.width),
            meter.heightAnchor.constraint(equalToConstant: 18),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])
    }

    func showListening() {
        meter.reset()
        show(meter: true, spinner: false, symbol: nil, text: "Listening")
    }

    /// Listening, with the words heard so far. When they do not fit, the
    /// oldest give way, so the newest stay in view.
    func showPreview(_ text: String) {
        show(meter: true, spinner: false, symbol: nil, text: text, keepEnd: true)
    }

    func setLevel(_ level: Float) {
        meter.push(CGFloat(level))
    }

    func showWorking() {
        show(meter: false, spinner: true, symbol: nil, text: "Transcribing")
    }

    /// A message that hides itself.
    func flash(_ text: String, symbol: String = "exclamationmark.circle", seconds: Double = 2.2) {
        show(meter: false, spinner: false, symbol: symbol, text: text)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        spinner.stopAnimation(nil)
        panel.orderOut(nil)
    }

    private func show(meter showMeter: Bool, spinner showSpinner: Bool, symbol: String?, text: String,
                      keepEnd: Bool = false) {
        hideTask?.cancel()
        hideTask = nil

        label.lineBreakMode = keepEnd ? .byTruncatingHead : .byTruncatingTail
        meter.isHidden = !showMeter
        spinner.isHidden = !showSpinner
        if showSpinner { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        icon.isHidden = symbol == nil
        icon.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        label.stringValue = text

        stack.layoutSubtreeIfNeeded()
        let size = NSSize(width: max(stack.fittingSize.width, 120), height: 40)
        panel.setFrame(NSRect(origin: origin(for: size), size: size), display: true)
        panel.orderFrontRegardless()
    }

    /// Bottom centre of the screen the pointer is on: where the user is looking.
    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: (frame.midX - size.width / 2).rounded(), y: frame.minY + 72)
    }
}

/// Rolling bars of recent input level, newest on the right.
final class LevelMeterView: NSView {
    static let barCount = 9
    static let barWidth: CGFloat = 3
    static let gap: CGFloat = 2
    static let width = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap

    private var levels = [CGFloat](repeating: 0, count: LevelMeterView.barCount)

    func reset() {
        levels = [CGFloat](repeating: 0, count: Self.barCount)
        needsDisplay = true
    }

    func push(_ level: CGFloat) {
        levels.removeFirst()
        levels.append(level)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setFill()
        let height = bounds.height
        for (index, level) in levels.enumerated() {
            let barHeight = max(3, height * level)
            let rect = NSRect(
                x: CGFloat(index) * (Self.barWidth + Self.gap),
                y: (height - barHeight) / 2,
                width: Self.barWidth,
                height: barHeight
            )
            NSBezierPath(roundedRect: rect, xRadius: Self.barWidth / 2, yRadius: Self.barWidth / 2).fill()
        }
    }
}
