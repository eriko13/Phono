import AppKit

/// The menu-bar icon: the wave from the app icon, drawn in code so it stays
/// sharp at any scale. It is a template image, so macOS colors it for light
/// and dark menu bars.
enum StatusIcon {
    enum State {
        case ready
        /// Loading or stopped: the wave is dimmed.
        case unavailable
        /// The wave cut out of a filled tile, like the app icon.
        case recording
    }

    static func image(_ state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let isRecording = state == .recording
            let wave = wavePath(
                in: rect.insetBy(dx: isRecording ? 5 : 2, dy: 0),
                amplitude: isRecording ? 3 : 4.5)
            wave.lineWidth = isRecording ? 1.6 : 1.8

            if isRecording {
                NSColor.black.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4.5, yRadius: 4.5).fill()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
            }
            NSColor.black.withAlphaComponent(state == .unavailable ? 0.35 : 1).setStroke()
            wave.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Phono"
        return image
    }

    /// One period of a sine wave across `rect`, rising first.
    private static func wavePath(in rect: NSRect, amplitude: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let steps = 48
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = NSPoint(x: rect.minX + rect.width * t, y: rect.midY + amplitude * sin(2 * .pi * t))
            if step == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        return path
    }
}
