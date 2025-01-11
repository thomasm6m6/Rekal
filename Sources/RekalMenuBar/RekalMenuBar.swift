import SwiftUI

@main
struct RekalMenuBar: App {    
    var body: some Scene {
        MenuBarExtra("Rekal", systemImage: "arrowtriangle.backward.fill") {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}