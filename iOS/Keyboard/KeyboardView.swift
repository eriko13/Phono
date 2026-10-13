import Observation
import SwiftUI

@MainActor
@Observable
final class KeyboardModel {
    enum Key { case space, `return`, delete }

    var state: KeyboardLink.State = .off
    var error: String?
    var hasFullAccess = true
    var showsNextKeyboard = true

    @ObservationIgnored var onMic: () -> Void = {}
    @ObservationIgnored var onNextKeyboard: () -> Void = {}
    @ObservationIgnored var onKey: (Key) -> Void = { _ in }
}

struct KeyboardView: View {
    let model: KeyboardModel

    var body: some View {
        VStack(spacing: 12) {
            status
                .font(.footnote)
                .foregroundStyle(model.error == nil ? Color.secondary : Color.red)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 32)

            micButton

            HStack(spacing: 8) {
                if model.showsNextKeyboard {
                    key("globe", label: "Next keyboard", action: model.onNextKeyboard)
                }
                Button { model.onKey(.space) } label: {
                    Text("space").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(KeyStyle())
                key("delete.left", label: "Delete") { model.onKey(.delete) }
                key("return", label: "Return") { model.onKey(.return) }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var status: some View {
        if !model.hasFullAccess {
            Text("Turn on Allow Full Access: Settings › Apps › Phono › Keyboards.")
        } else if let error = model.error {
            Text(error)
        } else {
            switch model.state {
            case .off: Text("Tap to open Phono and turn on the microphone.")
            case .ready: Text("Tap to talk")
            case .recording: Text("Listening…")
            case .transcribing: Text("Transcribing…")
            }
        }
    }

    private var micButton: some View {
        Button(action: model.onMic) {
            ZStack {
                Circle().fill(model.state == .recording ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                if model.state == .transcribing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: model.state == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
        .disabled(!model.hasFullAccess || model.state == .transcribing)
        .accessibilityLabel(model.state == .recording ? "Stop" : "Dictate")
    }

    private func key(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 52, height: 44)
        }
        .buttonStyle(KeyStyle())
        .accessibilityLabel(label)
    }
}

private struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: configuration.isPressed ? .systemGray4 : .secondarySystemBackground))
            )
    }
}
