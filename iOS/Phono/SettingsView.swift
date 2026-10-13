import PhonoCore
import PhonoKit
import SwiftUI

struct SettingsView: View {
    let settings: Settings
    let talk: TalkChannel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var key = ""
    @State private var check: Check = .none

    enum Check: Equatable {
        case none, checking, ok
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server URL", text: $url)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Phonon server")
                } footer: {
                    Text("For example `https://server.tailnet.ts.net`. iOS needs https. On a tailnet, `tailscale serve` gives the server an https address.")
                }

                Section {
                    Button("Test connection") { Task { await test() } }
                        .disabled(Server.baseURL(url) == nil || check == .checking)
                    switch check {
                    case .none: EmptyView()
                    case .checking: ProgressView()
                    case .ok: Label("Connected", systemImage: "checkmark.circle").foregroundStyle(.green)
                    case .failed(let message): Label(message, systemImage: "xmark.circle").foregroundStyle(.red)
                    }
                }

                Section {
                    Toggle("Talk button", isOn: Binding(
                        get: { talk.isJoined },
                        set: { $0 ? talk.join() : talk.leave() }
                    ))
                    if let error = talk.error {
                        Text(error).foregroundStyle(.red)
                    }
                    Button("Open Phono in Settings") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                } header: {
                    Text("Dictate in any app")
                } footer: {
                    Text("The Talk button sits in the status bar, like a walkie-talkie. Press it, speak, and press again: the Phono keyboard types the text. It works even after iOS closes Phono.\n\nUnder **Keyboards**, turn on Phono and Allow Full Access. The keyboard needs full access to get the text from this app. It sends nothing anywhere else.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") {
                    save()
                    dismiss()
                }
            }
            .onAppear {
                url = settings.serverURL
                key = settings.serverKey
            }
            .onChange(of: url) { check = .none }
            .onChange(of: key) { check = .none }
        }
    }

    private func save() {
        settings.serverURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.serverKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func test() async {
        guard let base = Server.baseURL(url) else { return }
        check = .checking
        do {
            try await ServerEngine(base: base, key: key.trimmingCharacters(in: .whitespacesAndNewlines)).checkConnection()
            check = .ok
            save()
        } catch {
            check = .failed(error.localizedDescription)
        }
    }
}
