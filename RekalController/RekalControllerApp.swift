import SwiftUI

@main
struct RekalControllerApp: App {
    @State var isRecording = true
    @State var snapshotCount = 0
    var xpcManager = XPCManager()

    var body: some Scene {
        MenuBarExtra {
            Group {
                Text("\(snapshotCount) queued snapshots")

                Button("Update counter") {
                    guard let session = xpcManager.session else {
                        log("No XPC session")
                        return
                    }

                    do {
                        let request = XPCRequest(messageType: .statusQuery(.imageCount))
                        let reply = try session.sendSync(request)
                        let response = try reply.decode(as: XPCResponse.self)

                        switch response.reply {
                        case .imageCount(let imageCount):
                            snapshotCount = imageCount
                        default:
                            break
                        }
                    } catch {
                        log("Failed to send message or decode reply: \(error)")
                    }
                }

                Button(isRecording ? "Pause recording" : "Resume recording") {
                    isRecording = !isRecording
                    // TODO
                }

//                Button("Update recording status") {
//                    guard let session = xpcManager.session else {
//                        return
//                    }
//
//                    do {
//                        let request = XPCRequest(messageType: .statusQuery(.recordingStatus))
//                        let reply = try session.sendSync(request)
//                        let response = try reply.decode(as: XPCResponse.self)
//
//                        DispatchQueue.main.async {
//                            log("Received response with reply: \(response.reply)")
//                        }
//                    } catch {
//                        log("Failed to send message or decode reply: \(error)")
//                    }
//                }

                Button("Process now") {
                    // TODO
                }
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                    // TODO this should quit daemon and GUI too
                }.keyboardShortcut("q")
            }
            .onAppear {
                xpcManager.setup()
            }
        } label: {
            MenuBarIcon(isRecording: $isRecording)
        }
    }
}

// TODO embed rotated icon as an asset
// TODO also it's not quite centered
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
