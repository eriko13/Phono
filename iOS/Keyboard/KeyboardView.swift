import UIKit

/// The keys and the bar above them, drawn like Apple's keyboard.
///
/// Touches are tracked by hand, so fast typing works as on Apple's keyboard:
/// a character is typed when its finger lifts, or when the next finger lands,
/// and a finger can slide to the character it meant. Holding a letter shows
/// its accents, and holding the space bar turns the keyboard into a trackpad
/// that moves the cursor.
final class KeyboardView: UIView {
    struct Configuration: Equatable {
        var page: Page = .letters
        var shift: Shift = .off
        var showsGlobe = false
        var returnTitle = "return"
        var returnIsBlue = false
        var returnEnabled = true
    }

    var configuration = Configuration() {
        didSet {
            guard configuration != oldValue else { return }
            if configuration.page != oldValue.page || configuration.showsGlobe != oldValue.showsGlobe {
                rebuildKeys()
            } else {
                keyViews.indices.forEach(refresh)
            }
        }
    }

    var onKey: (Key) -> Void = { _ in }
    /// Characters to move the cursor by, negative for left.
    var onCursor: (Int) -> Void = { _ in }

    let bar = TopBar()

    private var rows: [[Key]] = []
    private var keyViews: [KeyView] = []
    /// The key each finger is on, as an index into `keyViews`.
    private var touchKeys: [UITouch: Int] = [:]
    private let popup = PopupView()
    private var popupIndex: Int?
    private var deleteTimer: Timer?
    private var holdTimer: Timer?
    /// The key `holdTimer` waits on.
    private var holdIndex: Int?
    /// The finger choosing an accent, its key, and the panel of accents.
    private var accents: (touch: UITouch, index: Int)?
    private let accentPanel = AccentPanel()
    /// The finger moving the cursor, and where it last moved it.
    private var trackpad: (touch: UITouch, x: CGFloat)?
    /// Points of finger travel per character, like Apple's.
    private static let trackpadStep: CGFloat = 9

    init() {
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        addSubview(bar)
        popup.isUserInteractionEnabled = false
        popup.isHidden = true
        addSubview(popup)
        accentPanel.isUserInteractionEnabled = false
        accentPanel.isHidden = true
        addSubview(accentPanel)
        rebuildKeys()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private struct Metrics {
        let strip: CGFloat
        let top: CGFloat
        let rowGap: CGFloat
        let keyHeight: CGFloat
        let keyGap: CGFloat = 6
        let side: CGFloat = 3

        init(height: CGFloat) {
            let compact = height < 230
            strip = compact ? 28 : 38
            top = compact ? 4 : 6
            rowGap = compact ? 6 : 11
            keyHeight = (height - strip - top - 3 - 3 * rowGap) / 4
        }

        func rowTop(_ row: Int) -> CGFloat {
            strip + top + CGFloat(row) * (keyHeight + rowGap)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let metrics = Metrics(height: bounds.height)
        bar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: metrics.strip)
        popup.frame = bounds
        for (view, frame) in zip(keyViews, keyFrames(metrics)) {
            view.frame = frame
        }
    }

    /// Like Apple's: equal character keys, wider keys at the ends of the
    /// third row, and the space bar taking what the bottom row leaves.
    private func keyFrames(_ m: Metrics) -> [CGRect] {
        let width = bounds.width
        let unit = (width - 2 * m.side - 9 * m.keyGap) / 10
        let wide = (unit * 1.3).rounded()
        var frames: [CGRect] = []
        for (index, row) in rows.enumerated() {
            let y = m.rowTop(index)
            func add(_ x: CGFloat, _ w: CGFloat) {
                frames.append(CGRect(x: x, y: y, width: w, height: m.keyHeight))
            }
            switch index {
            case 0, 1:
                let count = CGFloat(row.count)
                var x = (width - count * unit - (count - 1) * m.keyGap) / 2
                for _ in row {
                    add(x, unit)
                    x += unit + m.keyGap
                }
            case 2:
                // The characters share the width of seven letter keys.
                let count = CGFloat(row.count - 2)
                let inner = 7 * unit + 6 * m.keyGap
                let w = (inner - (count - 1) * m.keyGap) / count
                add(m.side, wide)
                var x = (width - inner) / 2
                for _ in 0 ..< row.count - 2 {
                    add(x, w)
                    x += w + m.keyGap
                }
                add(width - m.side - wide, wide)
            default:
                let returnWidth = (unit * 2.5 + m.keyGap).rounded()
                let fixed = row.reduce(CGFloat(0)) { total, key in
                    switch key {
                    case .space: total
                    case .return: total + returnWidth
                    default: total + wide
                    }
                }
                let spaceWidth = width - 2 * m.side - fixed - CGFloat(row.count - 1) * m.keyGap
                var x = m.side
                for key in row {
                    let w: CGFloat = switch key {
                    case .space: spaceWidth
                    case .return: returnWidth
                    default: wide
                    }
                    add(x, w)
                    x += w + m.keyGap
                }
            }
        }
        return frames
    }

    private func rebuildKeys() {
        cancelTouches()
        keyViews.forEach { $0.removeFromSuperview() }
        rows = configuration.page.rows(showsGlobe: configuration.showsGlobe)
        keyViews = rows.joined().map { key in
            let view = KeyView(key: key)
            view.onActivate = { [weak self] in self?.onKey(key) }
            insertSubview(view, belowSubview: popup)
            return view
        }
        keyViews.indices.forEach(refresh)
        setNeedsLayout()
    }

    // MARK: Appearance

    private func refresh(_ index: Int) {
        let view = keyViews[index]
        let pressed = touchKeys.values.contains(index)
        let c = configuration
        switch view.key {
        case .character(let text):
            let shown = c.page == .letters && c.shift != .off ? text.uppercased() : text
            view.show(title: shown, fill: .keyCharacter)
        case .space:
            view.show(title: "space", fill: pressed ? .keyFunction : .keyCharacter, small: true)
        case .return:
            if c.returnIsBlue && c.returnEnabled {
                view.show(title: c.returnTitle, fill: pressed ? .keyFunction : .systemBlue, small: true, text: .white)
            } else {
                view.show(title: c.returnTitle, fill: pressed ? .keyCharacter : .keyFunction, small: true,
                          text: c.returnEnabled ? .label : .tertiaryLabel)
            }
        case .shift:
            switch c.shift {
            case .off: view.show(symbol: "shift", fill: pressed ? .keyCharacter : .keyFunction)
            case .once: view.show(symbol: "shift.fill", fill: .keyCharacter)
            case .locked: view.show(symbol: "capslock.fill", fill: .keyCharacter)
            }
        case .delete:
            view.show(symbol: pressed ? "delete.left.fill" : "delete.left", fill: pressed ? .keyCharacter : .keyFunction)
        case .nextKeyboard:
            view.show(symbol: "globe", fill: pressed ? .keyCharacter : .keyFunction)
        case .page(let page):
            let title = switch page {
            case .letters: "ABC"
            case .numbers: "123"
            case .symbols: "#+="
            }
            view.show(title: title, fill: pressed ? .keyCharacter : .keyFunction, small: true)
        }
    }

    private func showPopup(_ index: Int) {
        popupIndex = index
        popup.show(keyFrame: keyViews[index].frame, title: keyViews[index].title)
    }

    private func hidePopup() {
        popupIndex = nil
        popup.isHidden = true
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackpad == nil, accents == nil else { return }
        for touch in touches {
            guard let index = keyIndex(at: touch.location(in: self)) else { continue }
            // Typing fast, the next finger lands before the last one lifts.
            for (other, otherIndex) in touchKeys where keyViews[otherIndex].key.isCharacter {
                touchKeys[other] = nil
                release(otherIndex, typing: true)
            }
            touchKeys[touch] = index
            press(index)
            holdKey(index, touch)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let trackpad, touches.contains(trackpad.touch) {
            let x = trackpad.touch.location(in: self).x
            let steps = Int((x - trackpad.x) / Self.trackpadStep)
            if steps != 0 {
                self.trackpad?.x += CGFloat(steps) * Self.trackpadStep
                onCursor(steps)
            }
            return
        }
        if let accents, touches.contains(accents.touch) {
            accentPanel.select(at: accents.touch.location(in: accentPanel).x)
            return
        }
        touches.forEach(slide)
    }

    /// A finger on a character can slide to the one it meant.
    private func slide(_ touch: UITouch) {
        guard let index = touchKeys[touch], keyViews[index].key.isCharacter,
              let now = keyIndex(at: touch.location(in: self)), now != index,
              keyViews[now].key.isCharacter
        else { return }
        touchKeys[touch] = now
        if holdIndex == index { stopHold() }
        showPopup(now)
        holdKey(now, touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let trackpad, touches.contains(trackpad.touch) {
            endTrackpad()
            return
        }
        if let accents, touches.contains(accents.touch) {
            let chosen = accentPanel.selected
            endAccents()
            if let chosen { onKey(.character(chosen)) }
            return
        }
        for touch in touches {
            guard let index = touchKeys.removeValue(forKey: touch) else { continue }
            switch keyViews[index].key {
            case .character:
                release(index, typing: true)
            case .space, .return, .nextKeyboard:
                release(index, typing: keyIndex(at: touch.location(in: self)) == index)
            case .shift, .delete, .page:
                // These act when pressed.
                release(index, typing: false)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let trackpad, touches.contains(trackpad.touch) {
            endTrackpad()
            return
        }
        if let accents, touches.contains(accents.touch) {
            endAccents()
            return
        }
        for touch in touches {
            guard let index = touchKeys.removeValue(forKey: touch) else { continue }
            release(index, typing: false)
        }
    }

    private func press(_ index: Int) {
        UIDevice.current.playInputClick()
        let key = keyViews[index].key
        refresh(index)
        switch key {
        case .character:
            showPopup(index)
        case .delete:
            onKey(.delete)
            startDeleteRepeat()
        case .shift, .page:
            onKey(key)
        case .space, .return, .nextKeyboard:
            break
        }
    }

    private func release(_ index: Int, typing: Bool) {
        let key = keyViews[index].key
        if key == .delete { stopDeleteRepeat() }
        if holdIndex == index { stopHold() }
        if popupIndex == index { hidePopup() }
        refresh(index)
        if typing { onKey(key) }
    }

    private func cancelTouches() {
        touchKeys = [:]
        stopDeleteRepeat()
        stopHold()
        if trackpad != nil { endTrackpad() }
        if accents != nil { endAccents() }
        hidePopup()
    }

    /// The nearest key: the gaps between keys belong to the keys beside them.
    private func keyIndex(at point: CGPoint) -> Int? {
        guard !rows.isEmpty, point.y >= bar.frame.maxY else { return nil }
        let m = Metrics(height: bounds.height)
        let row = min(max(Int((point.y - m.rowTop(0) + m.rowGap / 2) / (m.keyHeight + m.rowGap)), 0), rows.count - 1)
        let start = rows[..<row].reduce(0) { $0 + $1.count }
        let indices = start ..< start + rows[row].count
        for index in indices.dropLast() where point.x < (keyViews[index].frame.maxX + keyViews[index + 1].frame.minX) / 2 {
            return index
        }
        return indices.last
    }

    // MARK: Hold

    /// Holding a key with accents shows them, and holding the space bar
    /// moves the cursor.
    private func holdKey(_ index: Int, _ touch: UITouch) {
        let key = keyViews[index].key
        if key == .space {
            startHold(index, after: 0.35) { [weak self] in self?.beginTrackpad(touch) }
        } else if !key.alternates.isEmpty {
            startHold(index, after: 0.4) { [weak self] in self?.beginAccents(touch) }
        }
    }

    /// Runs `action` if the key at `index` is still down after `delay`
    /// seconds.
    private func startHold(_ index: Int, after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        stopHold()
        holdIndex = index
        holdTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
    }

    private func stopHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdIndex = nil
    }

    // MARK: Accents

    private func beginAccents(_ touch: UITouch) {
        stopHold()
        guard let index = touchKeys[touch] else { return }
        let key = keyViews[index].key
        let capitals = configuration.page == .letters && configuration.shift != .off
        // Only this finger counts until it lifts.
        touchKeys = [:]
        hidePopup()
        refresh(index)
        accents = (touch, index)
        accentPanel.show(
            key.alternates.map { capitals ? $0.uppercased() : $0 },
            keyFrame: keyViews[index].frame,
            in: bounds
        )
    }

    private func endAccents() {
        accents = nil
        accentPanel.isHidden = true
    }

    // MARK: Trackpad

    private func beginTrackpad(_ touch: UITouch) {
        stopHold()
        guard let index = touchKeys[touch], keyViews[index].key == .space else { return }
        // Only this finger counts from now on.
        touchKeys = [:]
        hidePopup()
        trackpad = (touch, touch.location(in: self).x)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        keyViews.forEach { $0.isBlank = true }
        keyViews.indices.forEach(refresh)
        bar.alpha = 0
    }

    private func endTrackpad() {
        trackpad = nil
        keyViews.forEach { $0.isBlank = false }
        keyViews.indices.forEach(refresh)
        bar.alpha = 1
    }

    // MARK: Delete

    private func startDeleteRepeat() {
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onKey(.delete) }
                }
            }
        }
    }

    private func stopDeleteRepeat() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }
}

// MARK: - Key

private final class KeyView: UIView {
    let key: Key
    var onActivate: () -> Void = {}
    private(set) var title: String?
    /// While the space bar moves the cursor, the keys show nothing, as on
    /// Apple's keyboard.
    var isBlank = false {
        didSet {
            label.alpha = isBlank ? 0 : 1
            icon.alpha = isBlank ? 0 : 1
        }
    }

    private let shadow = UIView()
    private let face = UIView()
    private let label = UILabel()
    private let icon = UIImageView()

    init(key: Key) {
        self.key = key
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        for view in [shadow, face] {
            view.layer.cornerRadius = 9
            view.layer.cornerCurve = .continuous
            addSubview(view)
        }
        shadow.backgroundColor = .keyShadow
        label.textAlignment = .center
        face.addSubview(label)
        icon.contentMode = .center
        icon.tintColor = .label
        face.addSubview(icon)

        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        shadow.frame = bounds
        face.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - 1)
        label.frame = face.bounds
        icon.frame = face.bounds
    }

    func show(title: String, fill: UIColor, small: Bool = false, text: UIColor = .label) {
        self.title = title
        label.text = title
        label.font = small ? .systemFont(ofSize: 16) : .systemFont(ofSize: 24)
        label.textColor = text
        label.isHidden = false
        icon.isHidden = true
        face.backgroundColor = fill
        accessibilityLabel = title
    }

    func show(symbol: String, fill: UIColor) {
        title = nil
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular))
        icon.isHidden = false
        label.isHidden = true
        face.backgroundColor = fill
        accessibilityLabel = switch key {
        case .shift: "shift"
        case .delete: "delete"
        case .nextKeyboard: "next keyboard"
        default: symbol
        }
    }

    override func accessibilityActivate() -> Bool {
        onActivate()
        return true
    }
}

// MARK: - Pop-up

/// The enlarged key above a pressed character, joined to it like Apple's.
private final class PopupView: UIView {
    private var keyFrame: CGRect = .zero
    private var title = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(keyFrame: CGRect, title: String?) {
        self.keyFrame = keyFrame
        self.title = title ?? ""
        isHidden = false
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let key = keyFrame
        let headHeight = min(key.height, key.minY)
        let spread: CGFloat = 10
        let left = max(bounds.minX, key.minX - spread)
        let right = min(bounds.maxX, key.maxX + spread)
        let head = CGRect(x: left, y: key.minY - headHeight, width: right - left, height: headHeight * 0.85)
        let r: CGFloat = 9
        let path = UIBezierPath()
        path.move(to: CGPoint(x: key.minX, y: key.maxY - r))
        path.addLine(to: CGPoint(x: key.minX, y: key.minY + 4))
        path.addQuadCurve(to: CGPoint(x: head.minX, y: head.maxY - 4), controlPoint: CGPoint(x: key.minX, y: head.maxY))
        path.addLine(to: CGPoint(x: head.minX, y: head.minY + r))
        path.addQuadCurve(to: CGPoint(x: head.minX + r, y: head.minY), controlPoint: CGPoint(x: head.minX, y: head.minY))
        path.addLine(to: CGPoint(x: head.maxX - r, y: head.minY))
        path.addQuadCurve(to: CGPoint(x: head.maxX, y: head.minY + r), controlPoint: CGPoint(x: head.maxX, y: head.minY))
        path.addLine(to: CGPoint(x: head.maxX, y: head.maxY - 4))
        path.addQuadCurve(to: CGPoint(x: key.maxX, y: key.minY + 4), controlPoint: CGPoint(x: key.maxX, y: head.maxY))
        path.addLine(to: CGPoint(x: key.maxX, y: key.maxY - r))
        path.addQuadCurve(to: CGPoint(x: key.maxX - r, y: key.maxY), controlPoint: CGPoint(x: key.maxX, y: key.maxY))
        path.addLine(to: CGPoint(x: key.minX + r, y: key.maxY))
        path.addQuadCurve(to: CGPoint(x: key.minX, y: key.maxY - r), controlPoint: CGPoint(x: key.minX, y: key.maxY))
        path.close()
        UIColor.keyCharacter.setFill()
        path.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 34),
            .foregroundColor: UIColor.label,
        ]
        let size = title.size(withAttributes: attributes)
        title.draw(at: CGPoint(x: head.midX - size.width / 2, y: head.midY - size.height / 2), withAttributes: attributes)
    }
}

// MARK: - Accents

/// The accents of a held key, in a row above it like Apple's. The first is
/// nearest the key and chosen until the finger slides to another.
private final class AccentPanel: UIView {
    private var options: [String] = []
    /// Left to right on screen. Reversed near the right edge, so the first
    /// option stays next to the key.
    private var shown: [String] = []
    private var cells: [UILabel] = []
    private let panel = UIView()
    private(set) var selected: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        panel.backgroundColor = .keyCharacter
        panel.layer.cornerRadius = 9
        panel.layer.cornerCurve = .continuous
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.3
        panel.layer.shadowRadius = 3
        panel.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ options: [String], keyFrame key: CGRect, in bounds: CGRect) {
        self.options = options
        let width = max(key.width, 30)
        let total = width * CGFloat(options.count) + 8
        let growsLeft = key.midX > bounds.midX
        shown = growsLeft ? options.reversed() : options
        var x = growsLeft ? key.maxX + 4 - total : key.minX - 4
        x = min(max(x, bounds.minX + 2), bounds.maxX - total - 2)
        let height = key.height + 8
        frame = CGRect(x: x, y: max(key.minY - height - 4, 0), width: total, height: height)
        panel.frame = self.bounds

        cells.forEach { $0.removeFromSuperview() }
        cells = shown.enumerated().map { index, option in
            let cell = UILabel(frame: CGRect(x: 4 + CGFloat(index) * width, y: 4, width: width, height: key.height))
            cell.text = option
            cell.font = .systemFont(ofSize: 24)
            cell.textAlignment = .center
            cell.layer.cornerRadius = 7
            cell.layer.cornerCurve = .continuous
            cell.clipsToBounds = true
            panel.addSubview(cell)
            return cell
        }
        highlight(options.first)
        isHidden = false
    }

    /// `x` is in this view's coordinates.
    func select(at x: CGFloat) {
        guard !cells.isEmpty else { return }
        let width = cells[0].frame.width
        let index = min(max(Int((x - 4) / width), 0), cells.count - 1)
        highlight(shown[index])
    }

    private func highlight(_ option: String?) {
        selected = option
        for (cell, text) in zip(cells, shown) {
            let on = text == option
            cell.backgroundColor = on ? .systemBlue : .clear
            cell.textColor = on ? .white : .label
        }
    }
}

// MARK: - Colors

extension UIColor {
    static let keyCharacter = UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    }
    static let keyFunction = UIColor {
        $0.userInterfaceStyle == .dark
            ? UIColor(white: 0.27, alpha: 1)
            : UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1)
    }
    static let keyShadow = UIColor {
        $0.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.6)
            : UIColor(red: 0.53, green: 0.54, blue: 0.56, alpha: 1)
    }
}
