import SwiftUI
import Vision

// TODO make "open rekal" function properly
// TODO alternative to passing frameManager manually to every custom view?

struct ContentView: View {
    @StateObject private var frameManager = FrameManager()
    @State private var selectedDate = Date()
    var xpcManager: XPCManager

    private let backgroundColor = Color(red: 18/256, green: 18/256, blue: 18/256) // #121212

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            NavigationStack {
                ImageView(frameManager: frameManager)
            }
            .toolbar {
                Toolbar(frameManager: frameManager, xpcManager: xpcManager)
            }
            .toolbarBackground(backgroundColor)
        }
        .onAppear {
            _ = LaunchManager.registerLaunchAgent()
            xpcManager.setup()
            fetchImages()

            _ = LaunchManager.registerLoginItem()
        }
    }

    func fetchImages() {
        // TODO fetch all(?) the in-memory images, asynchronously
        if let session = xpcManager.session {
            do {
                let request = XPCRequest(messageType: .fetchImages)
                let reply = try session.sendSync(request)
                let response = try reply.decode(as: XPCResponse.self)

                DispatchQueue.main.async {
                    switch response.reply {
                    case .snapshots(let encodedSnapshots):
                        frameManager.snapshots = decodeSnapshots(encodedSnapshots)
                    default:
                        log("TODO")
                    }
                }
            } catch {
                log("Failed to send message or decode reply: \(error)")
            }
        } else {
            log("No XPC session")
        }
    }
}

struct ImageView: View {
    @StateObject var frameManager: FrameManager
    @State private var showOCRView = false
    @State private var delayTask: Task<Void, Never>?

    var body: some View {
        VStack {
            Spacer()

            if !frameManager.snapshots.isEmpty {
                let timestamp = frameManager.snapshots.keys[frameManager.index]
                if let snapshot = frameManager.snapshots[timestamp],
                   let image = snapshot.image {
                    Group {
                        Image(image, scale: 1.0, label: Text("Screenshot"))
                            .resizable()
                            .scaledToFit()
                            .onChange(of: image, initial: true) {
                                showOCRView = false
                                delayTask?.cancel()

                                delayTask = Task {
                                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                                    if !Task.isCancelled {
                                        showOCRView = true
                                    }
                                }
                            }
                            .overlay {
                                if showOCRView {
                                    OCRView(snapshot: snapshot)
                                }
                            }
                    }
                    .padding()
                } else {
                    Text("Failed to get the image")
                }
            } else {
                Text("No images to display")
            }

            Spacer()
        }
    }
}
