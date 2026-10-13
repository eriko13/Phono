import SwiftUI

@main
struct PhonoApp: App {
    @State private var dictation = Dictation()

    var body: some Scene {
        WindowGroup {
            ContentView(dictation: dictation)
                .onOpenURL { url in
                    guard url == KeyboardLink.openURL else { return }
                    Task { await dictation.startKeyboardSession() }
                }
        }
    }
}
