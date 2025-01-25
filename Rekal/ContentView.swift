import SwiftUI
import Vision
import ServiceManagement

// TODO padding around images?
// TODO settings page
// TODO make "open rekal" function properly
// TODO cmd+f or "/" to focus search
// TODO make image exportable

class LaunchManager {
    private static let launchAgentPlist = "com.thomasm6m6.RekalAgent.plist"

    static func registerLoginItem() -> Bool {
        let service = SMAppService.mainApp
        do {
            try service.register()
            log("Registered login item")
            return true
        } catch {
            log("Error registering login item: \(error)")
            return false
        }
    }

    static func unregisterLoginItem() -> Bool {
        let service = SMAppService.mainApp
        do {
            try service.unregister()
            log("Unregistered login item")
            return true
        } catch {
            log("Error unregistering login item: \(error)")
            return false
        }
    }

    static func getLoginItemStatus() -> SMAppService.Status {
        let service = SMAppService.mainApp
        return service.status
    }

    static func registerLaunchAgent() -> Bool {
        let service = SMAppService.agent(plistName: launchAgentPlist)
        do {
            try service.register()
            log("Registered launch agent")
            return true
        } catch {
            log("Error registering launch agent: \(error)")
            return false
        }
    }

    static func unregisterLaunchAgent() -> Bool {
        let service = SMAppService.agent(plistName: launchAgentPlist)
        do {
            try service.unregister()
            log("Unregistered launch agent")
            return true
        } catch {
            log("Error unregistering launch agent: \(error)")
            return false
        }
    }

    static func getLaunchAgentStatus() -> SMAppService.Status {
        let service = SMAppService.agent(plistName: launchAgentPlist)
        return service.status
    }
}

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

struct Toolbar: View {
    @StateObject var frameManager: FrameManager
    @State var isInfoShowing = false
    var xpcManager: XPCManager

    var body: some View {
        Button("Previous", systemImage: "chevron.left", action: previousImage)
            .disabled(frameManager.snapshots.isEmpty || frameManager.index < 1)

        Button("Next", systemImage: "chevron.right", action: nextImage)
            .disabled(frameManager.snapshots.isEmpty || frameManager.index >= frameManager.snapshots.count-1)

        Text("\(frameManager.snapshots.count == 0 ? 0 : frameManager.index + 1)/\(frameManager.snapshots.count)")
            .font(.system(.body, design: .monospaced))

        Spacer()
        
        SearchBar(frameManager: frameManager)

        Spacer()

        Button("Unregister") {
            _ = LaunchManager.unregisterLaunchAgent()
            _ = LaunchManager.unregisterLoginItem()
        }

        Button("Process now") {
            // TODO fetch all(?) the in-memory images, asynchronously
            if let session = xpcManager.session {
                do {
                    let request = XPCRequest(messageType: .controlCommand(.processImages))
                    let reply = try session.sendSync(request)
                    let response = try reply.decode(as: XPCResponse.self)

                    DispatchQueue.main.async {
                        switch response.reply {
                        case .snapshots(let encodedSnapshots):
                            frameManager.snapshots = decodeSnapshots(encodedSnapshots)
                        case .didProcess:
                            log("Processing succeeded")
                        case .error(let error):
                            log("Processing error: \(error)")
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

        Button("Info", systemImage: "info.circle") {
            isInfoShowing = true
        }
        .disabled(frameManager.snapshots.isEmpty)
        .popover(isPresented: $isInfoShowing, arrowEdge: .bottom) {
            let key = frameManager.snapshots.keys[frameManager.index]
            if let snapshot = frameManager.snapshots[key] {
                let info = snapshot.info

                Group {
                    let date = Date(timeIntervalSince1970: TimeInterval(snapshot.timestamp))
                    Text("Time: \(date)")

                    if let windowName = info.windowName {
                        Text("Window name: \(windowName)")
                    }

                    if let appName = info.appName {
                        Text("App name: \(appName)")
                    }

                    if let appId = info.appId {
                        Text("App ID: \(appId)")
                    }

                    if let url = info.url {
                        Text("URL: \(url)")
                    }
                }
                .padding()
            }
        }
    }

    func previousImage() {
        frameManager.decrementIndex()
    }

    func nextImage() {
        frameManager.incrementIndex()
    }
}

struct SearchBar: View {
    var frameManager: FrameManager
    @State var isShowingPopover = false
    @State var fullTextSearch = false
    @State var searchText = ""

    var body: some View {
        // FIXME doesn't appear in overflow menu
        // FIXME not centered
        // FIXME styling is hacky
        // TODO make search box stand out somehow (rgb(30,30,30) background)
        TextField("Search...", text: $searchText)
            .textFieldStyle(.roundedBorder)
        //                    .background(.red.opacity(0.5))
        //                    .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: 300)
            .onSubmit {
                let options = SearchOptions(
                    fullText: fullTextSearch
                )
                frameManager.extractFrames(search: searchText, options: options)
            }

        Button("Search options", systemImage: "slider.horizontal.3") {
            isShowingPopover = true
        }
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            Toggle(isOn: $fullTextSearch) {
                Text("Full-text search")
            }
            .padding()
        }
    }
}
