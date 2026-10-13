import AppKit
import ApplicationServices
import AVFoundation

/// The two permissions Phono uses:
/// - Microphone, to record while the shortcut is active.
/// - Accessibility, to see a lone ⌥ or fn, and to paste with ⌘V or type.
enum Permissions {
    static let accessibilityPane = "com.apple.preference.security?Privacy_Accessibility"
    static let microphonePane = "com.apple.preference.security?Privacy_Microphone"
    static let keyboardPane = "com.apple.Keyboard-Settings.extension"

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt for Accessibility, unless already granted.
    static func promptAccessibility() {
        // The string value of `kAXTrustedCheckOptionPrompt`, which Swift 6
        // rejects as a non-Sendable global.
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static var isMicrophoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var isMicrophoneUndetermined: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
    }

    static var microphoneStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "granted"
        case .notDetermined: return "not asked yet"
        case .denied: return "denied"
        case .restricted: return "restricted"
        @unknown default: return "unknown"
        }
    }

    /// Asks the first time; after a "no", only System Settings can change it.
    @MainActor
    static func requestMicrophone() {
        if isMicrophoneUndetermined {
            Task { _ = await AVCaptureDevice.requestAccess(for: .audio) }
        } else if !isMicrophoneGranted {
            openSettings(microphonePane)
        }
    }

    @MainActor
    static func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
