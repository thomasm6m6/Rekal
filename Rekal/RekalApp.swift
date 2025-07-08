import SwiftUI

// FIXME: if the program is quit, the daemon will remain running. The daemon may have been left in a paused state.
// The program always assumes at launch that the daemon is in a resumed state.

@main
struct RekalApp: App {
    @State var isRecording = true
    @State var snapshotCount = 0
    @StateObject var imageModel = ImageModel()

//    var xpcManager = XPCManager.shared
//    @FocusState var isSearchFocused: Bool

    var body: some Scene {
        WindowGroup(id: "main-window") {
            ContentView(imageModel: imageModel)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                }
                .onDisappear {
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
//                .onKeyPress { key in
//                    isSearchFocused = true
//                    return .ignored
//                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            VStack {
                Button(isRecording ? "Pause recording" : "Resume recording") {
                    Task {
                        do { // is do-catch necessary inside Task?
                            isRecording = try await imageModel.setRecording(!isRecording)
                        } catch {
                            print("Error setting recording status: \(error)")
                        }
                    }
                    //                isRecording.toggle()
                    //                imageModel.xpcManager.toggleRecording()
                }

                Button("Sync") {}

                OpenWindowButton()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                    // TODO: should quit daemon as well, if option was held(?)
                }.keyboardShortcut("q")
            }
        } label: {
            MenuBarIcon(isRecording: $isRecording)
        }
    }
}

struct OpenWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open") {
            openWindow(id: "main-window")
        }
    }
}

// TODO: embed rotated icon as an asset
// TODO: also it's not quite centered
struct MenuBarIcon: View {
    @Binding var isRecording: Bool

    var body: some View {
        // Would use "arrowtriangle.backward" but it's not equilateral
        Image(nsImage: createRotatedImage(
            systemName: isRecording ? "triangle.fill" : "triangle",
            degrees: 90
        ))
    }

    func createRotatedImage(systemName: String, degrees: CGFloat) -> NSImage {
        let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)!

        let radians = degrees * .pi / 180
        let newSize = CGSize(width: symbol.size.height, height: symbol.size.width)

        let rotatedImage = NSImage(size: newSize, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            let transform = NSAffineTransform()
            transform.translateX(by: rect.width / 2, yBy: rect.height / 2)
            transform.rotate(byRadians: radians)
            transform.translateX(by: -rect.size.width / 2, yBy: -rect.size.height / 2)
            transform.concat()

            symbol.draw(
                at: .zero,
                from: CGRect(origin: .zero, size: symbol.size),
                operation: .sourceOver,
                fraction: 1.0
            )

            return true
        }

        rotatedImage.isTemplate = true
        return rotatedImage
    }
}
