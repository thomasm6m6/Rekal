import SwiftUI
import Vision
import ServiceManagement

// TODO border around images?
// TODO settings page
// TODO make "open rekal" function properly

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
//    @State private var showOCRView = false
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
                Toolbar(frameManager: frameManager)
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

struct OCRView: View {
    @State private var isSelected = false
    @State private var isHovering = false
    @State private var ocrResults: [OCRResult]? = nil
    var snapshot: Snapshot

    var body: some View {
        if let ocrResults = ocrResults {
            ForEach(ocrResults, id: \.uuid) { result in
                GeometryReader { geometry in
                    let boundingBox = NormalizedRect(normalizedRect: result.normalizedRect)
                    let rect = boundingBox.toImageCoordinates(geometry.size, origin: .upperLeft)
                    Rectangle()
                        .fill(isSelected ? .green : .blue)
                        .contentShape(Rectangle())
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .onTapGesture(count: 2) {
                            isSelected = true
                        }
                        .onTapGesture(count: 1) {
                            isSelected = false
                        }
                        .onHover { hovering in
                            isHovering = hovering
                            if hovering {
                                NSCursor.iBeam.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                }
            }
        }
        // Without this, nothing appears until ocrResults != nil,
        // but ocrResults == nil until something appears
        // TODO there must be a better solution
        Rectangle()
            .frame(width: 0, height: 0)
            .onAppear {
                loadOCRResults(snapshot: snapshot)
            }
    }

    // TODO save OCR data to daemon memory space
    func loadOCRResults(snapshot: Snapshot) {
        Task {
            do {
                var ocrData: String?

                if snapshot.ocrData == nil {
                    if let image = snapshot.image {
                        ocrData = try await performOCR(on: image)
                    }
                } else {
                    ocrData = snapshot.ocrData
                }

                if let ocrData = ocrData, let jsonData = ocrData.data(using: .utf8) {
                    let decoder = JSONDecoder()
                    let results = try decoder.decode([OCRResult].self, from: jsonData)
                    await MainActor.run {
                        ocrResults = results
                    }
                }
            } catch {
                log("OCR failed: \(error)")
            }
        }
    }
}

struct Toolbar: View {
    @StateObject var frameManager: FrameManager
    @State private var searchText = ""

    var body: some View {
        Button("Previous", systemImage: "chevron.left", action: previousImage)
            .disabled(frameManager.snapshots.isEmpty || frameManager.index < 1)

        Button("Next", systemImage: "chevron.right", action: nextImage)
            .disabled(frameManager.snapshots.isEmpty || frameManager.index >= frameManager.snapshots.count-1)

        Text("\(frameManager.snapshots.count == 0 ? 0 : frameManager.index + 1)/\(frameManager.snapshots.count)")
            .font(.system(.body, design: .monospaced))

        Spacer()

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
                frameManager.extractFrames(query: searchText)
            }

        Spacer()

        Button("Unregister") {
            _ = LaunchManager.unregisterLaunchAgent()
            _ = LaunchManager.unregisterLoginItem()
        }

        Button("Process now") {
            //
        }

        Button("Info", systemImage: "info.circle", action: showInfo)
            .disabled(frameManager.snapshots.isEmpty)
    }

    func previousImage() {
        frameManager.decrementIndex()
    }

    func nextImage() {
        frameManager.incrementIndex()
    }

    func showInfo() {
    }
}
