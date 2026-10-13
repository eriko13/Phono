import SwiftUI

struct ContentView: View {
    let dictation: Dictation
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if dictation.keyboardSession { keyboardBanner }
                transcripts
                status
                RecordButton(state: dictation.state, level: dictation.level) {
                    Task { await dictation.toggle() }
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("Phono")
            .toolbar {
                Button("Settings", systemImage: "gearshape") { showsSettings = true }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView(settings: dictation.settings)
            }
            .onAppear {
                if !dictation.hasServer { showsSettings = true }
            }
        }
    }

    @ViewBuilder private var transcripts: some View {
        if dictation.transcripts.isEmpty {
            ContentUnavailableView(
                "Tap to talk",
                systemImage: "waveform",
                description: Text("Tap the button, speak, and tap again. The text is copied for you.")
            )
        } else {
            List(Array(dictation.transcripts.enumerated()), id: \.offset) { _, text in
                Button {
                    dictation.copy(text)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text).foregroundStyle(.primary)
                        if text == dictation.copied {
                            Text("Copied").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var keyboardBanner: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Keyboard is on", systemImage: "keyboard").font(.headline)
                Text("Go back to your app and talk. The microphone turns off 5 minutes after your last clip.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Turn off") { dictation.endKeyboardSession() }
                .buttonStyle(.bordered)
        }
        .padding()
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var status: some View {
        Group {
            switch dictation.state {
            case .idle: Text(" ")
            case .recording: Text("Listening…")
            case .transcribing: Text("Transcribing…")
            case .failed(let message): Text(message).foregroundStyle(.red)
            }
        }
        .font(.callout)
        .multilineTextAlignment(.center)
        .padding()
    }
}

private struct RecordButton: View {
    let state: Dictation.State
    let level: Float
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.tint.opacity(0.2))
                    .scaleEffect(state == .recording ? 1 + CGFloat(level) * 0.4 : 1)
                    .animation(.easeOut(duration: 0.1), value: level)
                Circle()
                    .fill(state == .recording ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                    .padding(12)
                if state == .transcribing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: state == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 96, height: 96)
        }
        .buttonStyle(.plain)
        .disabled(state == .transcribing)
        .accessibilityLabel(state == .recording ? "Stop" : "Record")
    }
}
