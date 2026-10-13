import SwiftUI

@main
struct PhonoApp: App {
    @State private var dictation = Dictation()

    var body: some Scene {
        WindowGroup {
            ContentView(dictation: dictation)
        }
    }
}
