import SwiftUI

@main
struct RekalControllerApp: App {
    @State private var isRecording = true

    var body: some Scene {
        MenuBarExtra {
            Text("N queued snapshots")

            Button(isRecording ? "Pause recording" : "Resume recording") {
                isRecording = !isRecording
                // TODO
            }
            
            Button("Process now") {
                // TODO
            }
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
                // TODO this should quit daemon and GUI too
            }.keyboardShortcut("q")
        } label: {
            MenuBarIcon(isRecording: $isRecording)
        }
    }
}

// TODO embed rotated icon as an asset
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
