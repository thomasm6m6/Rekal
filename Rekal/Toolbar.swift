import SwiftUI

// TODO UserDefaults for search options

struct Toolbar: View {
    @StateObject var frameManager: FrameManager
    @State var isInfoShowing = false
    var xpcManager: XPCManager

    var body: some View {
        NavigationView(frameManager: frameManager)

        Spacer()

        SearchBar(frameManager: frameManager, xpcManager: xpcManager)

        Spacer()

        Button("Process now") {
            processNow()
        }

        InfoButton(frameManager: frameManager)
    }

    func processNow() {
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
}

struct NavigationView: View {
    @StateObject var frameManager: FrameManager

    var body: some View {
        Button("Previous", systemImage: "chevron.left", action: frameManager.previousImage)
            .disabled(frameManager.snapshots.isEmpty || frameManager.index < 1)

        Button("Next", systemImage: "chevron.right", action: frameManager.nextImage)
            .disabled(frameManager.snapshots.isEmpty || frameManager.index >= frameManager.snapshots.count-1)

        let count = frameManager.snapshots.count
        Text("\(count == 0 ? 0 : frameManager.index + 1)/\(count)")
            .font(.system(.body, design: .monospaced))
    }
}

struct SearchBar: View {
    @StateObject var frameManager: FrameManager
    @State var isShowingPopover = false
    @State var fullTextSearch = false
    @State var searchText = ""
    var xpcManager: XPCManager

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
                frameManager.extractFrames(search: searchText, options: options, xpcManager: xpcManager)
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

struct InfoButton: View {
    @StateObject var frameManager: FrameManager
    @State private var isInfoShowing = false

    var body: some View {
        Button("Info", systemImage: "info.circle") {
            isInfoShowing = true
        }
        .disabled(frameManager.snapshots.isEmpty)
        .popover(isPresented: $isInfoShowing, arrowEdge: .bottom) {
            let key = frameManager.snapshots.keys[frameManager.index]
            if let snapshot = frameManager.snapshots[key] {
                let info = snapshot.info

                VStack {
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
                    
                    // FIXME don't seem to show the URL ever
                    if let url = info.url {
                        Text("URL: \(url)")
                    }
                }
                .padding()
            }
        }
    }
}
