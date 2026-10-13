import Observation
import SwiftUI

@MainActor
@Observable
final class KeyboardModel {
    var state: KeyboardLink.State = .idle
    var error: String?
    var hasFullAccess = true
    var showsNextKeyboard = true

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

            HStack(spacing: 8) {
                if model.showsNextKeyboard {
                    key("globe", label: "Next keyboard", action: { model.onKey(.nextKeyboard) })
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
            case .idle: Text("Press Talk at the top of the screen to dictate.")
            case .recording: Text("Listening…")
            case .transcribing: Text("Transcribing…")
            }
        }
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
