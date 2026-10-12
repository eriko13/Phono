import AppKit

/// A menu item whose action, title, checkmark, and visibility are closures,
/// so the menu is built as one list and refreshed by one `reload()` walk.
@MainActor
final class MenuItem: NSMenuItem {
    private let handler: (() -> Void)?
    private let liveTitle: (() -> String)?
    private let isOn: (() -> Bool)?
    private let isShown: (() -> Bool)?

    /// An item that runs `handler` when chosen. `handler` is required, so a
    /// trailing closure always binds to it, never to the optional closures.
    convenience init(
        _ title: String,
        key: String = "",
        isOn: (() -> Bool)? = nil,
        isShown: (() -> Bool)? = nil,
        handler: @escaping () -> Void
    ) {
        self.init(title, key: key, liveTitle: nil, isOn: isOn, isShown: isShown, submenu: nil, handler: handler)
    }

    /// Inactive text, or a submenu when `submenu` is given.
    convenience init(
        _ title: String = "",
        liveTitle: (() -> String)? = nil,
        isShown: (() -> Bool)? = nil,
        submenu: NSMenu? = nil
    ) {
        self.init(title, key: "", liveTitle: liveTitle, isOn: nil, isShown: isShown, submenu: submenu, handler: nil)
    }

    private init(
        _ title: String,
        key: String,
        liveTitle: (() -> String)?,
        isOn: (() -> Bool)?,
        isShown: (() -> Bool)?,
        submenu: NSMenu?,
        handler: (() -> Void)?
    ) {
        self.handler = handler
        self.liveTitle = liveTitle
        self.isOn = isOn
        self.isShown = isShown
        super.init(title: title, action: handler == nil ? nil : #selector(run), keyEquivalent: key)
        target = self
        self.submenu = submenu
        isEnabled = handler != nil || submenu != nil
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("MenuItem is built in code")
    }

    @objc private func run() {
        handler?()
    }

    /// Re-reads every closure, here and in the submenu.
    func reload() {
        if let liveTitle { title = liveTitle() }
        if let isOn { state = isOn() ? .on : .off }
        if let isShown { isHidden = !isShown() }
        submenu?.items.forEach { ($0 as? MenuItem)?.reload() }
    }
}

/// A menu whose items keep the enabled state they were given.
@MainActor
func makeMenu(_ items: [NSMenuItem]) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.items = items
    return menu
}
