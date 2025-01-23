import SwiftUI

// Should RekalController and RekalAgent be added as build deps of Rekal?

@main
struct RekalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
