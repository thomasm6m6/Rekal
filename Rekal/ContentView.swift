import SwiftUI
import XPC
import Vision
import AVFoundation

// TODO: make "open rekal" function properly
// TODO: alternative to passing frameManager manually to every custom view?
// TODO: use `public`/`private`/`@Published` correctly
// FIXME: "onChange(of: CGImageRef) action tried to update multiple times per frame"
// TODO: easily noticeable warning (maybe a popup, and/or an exclamation point through the menu bar icon) if the record function throws when it shouldn't
// FIXME: applescript
// TODO: combine frameManager, xpcManager, etc into a ContextManager?
// TODO: search bar doesn't show in overflow menu when window width is small

struct SearchOptions {
    var fullText: Bool
}

struct Search {
    var minTimestamp: Int
    var maxTimestamp: Int
    var terms: [String]

    static func parse(text: String) -> Search {
        let today = Int(Calendar.current.startOfDay(for: Date.now).timeIntervalSince1970)
        return Search(
            minTimestamp: today,
            maxTimestamp: today + 24 * 60 * 60,
            terms: []
        )
    }
}

struct ContentView: View {
    @FocusState private var isFocused: Bool

    @StateObject private var imageModel = ImageModel()

    private let backgroundColor = Color(red: 18/256, green: 18/256, blue: 18/256) // #121212

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            // FIXME: clicking outside the imageview (ie in the blank area of the window)
            // makes it unresponsive to arrow keys
            NavigationStack {
                VStack {
                    Spacer()

                    if !imageModel.snapshots.isEmpty,
                       let image = imageModel.snapshots[imageModel.index].image {
                        Group {
                            Image(image, scale: 1.0, label: Text("Screenshot"))
                                .resizable()
                                .scaledToFit()
                        }
                        .padding()
                    } else {
                        Text("No images found")
                    }

                    Spacer()
                }
                .onAppear {
                    imageModel.loadImages()
                    isFocused = true
                }
                .focusable()
                .focused($isFocused)
                .focusEffectDisabled()
                .onKeyPress(.leftArrow) {
                    imageModel.previousImage()
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    imageModel.nextImage()
                    return .handled
                }
            }
            .toolbar {
                Toolbar(imageModel: imageModel)
            }
            .toolbarBackground(backgroundColor)
        }
        .onAppear {
            _ = LaunchManager.registerLoginItem()
            _ = LaunchManager.registerLaunchAgent()
        }
    }
}
