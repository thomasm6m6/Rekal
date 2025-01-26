import SwiftUI
import Vision

// TODO make "open rekal" function properly
// TODO alternative to passing frameManager manually to every custom view?
// TODO use `public`/`private`/`@Published` correctly
// FIXME images are displayed out of order
// FIXME "onChange(of: CGImageRef) action tried to update multiple times per frame"
// TODO easily noticeable warning (maybe a popup, and/or an exclamation point through the menu bar icon) if the record function throws when it shouldn't
// FIXME applescript
// FIXME "Publishing changes from within view updates is not allowed, this will cause undefined behavior" (nextImage/previousImage)

struct ContentView: View {
    var xpcManager: XPCManager

    @StateObject var frameManager = FrameManager()
    @State private var selectedDate = Date()
    @FocusState private var focused: Bool

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
            frameManager.extractFrames(
                search: "",
                options: SearchOptions(fullText: false),
                xpcManager: xpcManager
            )

            _ = LaunchManager.registerLoginItem()
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear {
            focused = true
        }
        .onKeyPress(.leftArrow) {
            frameManager.previousImage()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            frameManager.nextImage()
            return .handled
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
