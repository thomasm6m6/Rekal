import SwiftUI

// TODO: make "open rekal" function properly
// TODO: alternative to passing frameManager manually to every custom view?
// TODO: use `public`/`private`/`@Published` correctly
// TODO: easily noticeable warning (maybe a popup, and/or an exclamation point through the menu bar icon) if the record function throws when it shouldn't
// FIXME: applescript
// TODO: combine frameManager, xpcManager, etc into a ContextManager?
// TODO: search bar doesn't show in overflow menu when window width is small

struct ContentView: View {
    @FocusState private var isFocused: Bool
    @StateObject var imageModel: ImageModel
//    @StateObject private var imageModel = ImageModel()

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

                    if !imageModel.snapshots.isEmpty, let image = imageModel.snapshots[imageModel.index].image {
                        Group {
                            Image(image, scale: 1.0, label: Text("Screenshot"))
                                .resizable()
                                .scaledToFit()
                                .contextMenu {
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setData(image.png, forType: .png)
                                    }
                                }
                        }
                        .padding()
                    } else {
                        ProgressView()
                    }

                    Spacer()
                }
                .onAppear {
                    imageModel.loadImages(query: Query())
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
