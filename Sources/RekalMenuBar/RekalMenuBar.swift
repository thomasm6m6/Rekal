import SwiftUI

// TODO XPC with daemon
// TODO launchd
// TODO rename this (RekalMenuBarApp?)
// TODO display a dynamic count of unprocessed images (including the timestamp of the oldest unprocessed image)

@main
struct RekalMenuBar: App {
    @State var recording = true

    var body: some Scene {
        MenuBarExtra("Rekal", systemImage: recording ? "arrowtriangle.backward.fill" : "arrowtriangle.backward") {
            Button(recording ? "Pause recording" : "Resume recording") {
                recording = !recording
                print(recording ? "recording paused" : "recording resumed")
            }
            Button("Process now") {
                print("process now")
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
                // should this also quit the daemon? what about the GUI?
            }.keyboardShortcut("q")
        }
    }
}