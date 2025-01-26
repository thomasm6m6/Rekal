import SwiftUI

struct SettingsView: View {
    var body: some View {
        HStack {
            Button("Unregister launch agent") {
                _ = LaunchManager.unregisterLaunchAgent()
            }
        }
        .padding()
    }
}
