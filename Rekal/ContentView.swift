import SwiftUI
import ServiceManagement

// TODO border around images?
// TODO settings page

class LaunchManager {
    private static let loginItemId = "com.thomasm6m6.RekalController"
    private static let launchAgentPlist = "com.thomasm6m6.RekalAgent.plist"

    static func registerLoginItem() -> Bool {
        let service = SMAppService.loginItem(identifier: loginItemId)
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
        let service = SMAppService.loginItem(identifier: loginItemId)
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
        let service = SMAppService.loginItem(identifier: loginItemId)
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

//struct OCRGroup: View {
//    var snapshot: Snapshot

//    var body: some View {
//        Group {
            // TODO make ocrData optional type
//            if snapshot.ocrData.count > 0 {
//                if let ocrResults = try? decodeOCR(data: snapshot.ocrData) {
//                    ForEach(ocrResults, id: \.uuid) { result in
//                        OCRView(result.text, normalizedRect: result.normalizedRect)
//                    }
//                }
//            } else if let image = snapshot.image {
//                if let ocrResults = try? await performOCR(on: image) {
//                    ForEach(ocrResults, id: \.uuid) { result in
//                        OCRView(result.text, normalizedRect: result.normalizedRect)
//                    }
//                }
//            }
//        }
//    }

//    var body: some View {
//        Group {
////            let ocrResults = getOCR(for: snapshot)
//            ForEach(ocrResults, id: \.uuid) { result in
//                OCRView(result.text, normalizedRect: result.normalizedRect)
//            }
//        }
//    }

//    func decodeOCR(data jsonString: String) throws -> [OCRResult] {
//        guard let jsonData = jsonString.data(using: .utf8) else {
//            throw OCRError.error("Cannot decode json")
//        }
//        let decoder = JSONDecoder()
//        let results = try decoder.decode([OCRResult].self, from: jsonData)
//        return results
//    }
//
//    func getOCR(for snapshot: Snapshot) async -> [OCRResult] {
//        log("getOCR(\(snapshot.timestamp))")
//        if snapshot.ocrData.count > 0 {
//            var results: [OCRResult] = []
//
//            do {
//                results = try decodeOCR(data: snapshot.ocrData)
//            } catch {
//                print("decodeOCR error: \(error)")
//            }
//            return results
//        }
//
//        guard let image = snapshot.image else {
//            return []
//        }
//
//        let semaphore = DispatchSemaphore(value: 0)
//        var ocrData: String?
//        var results: [OCRResult] = []
//
//        do {
//            ocrData = try await performOCR(on: image)
//            if let ocrData = ocrData {
//                do {
//                    results = try decodeOCR(data: ocrData)
//                } catch {
//                    print("OCR error: \(error)")
//                }
//            }
//        } catch {
//            print("OCR error: \(error)")
//        }
//
//        return results
//    }
//}
//
struct ContentView: View {
    @StateObject private var frameManager = FrameManager()
    @State private var selectedDate = Date()
    @State private var searchText = ""
    let xpcManager = XPCManager()
//    @State var ocrResults: [OCRResult] = []

    private let backgroundColor = Color(red: 18/256, green: 18/256, blue: 18/256) // #121212

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            NavigationStack {
                VStack {
                    Spacer()

                    if !frameManager.snapshots.isEmpty {
                        let timestamp = frameManager.snapshots.keys[frameManager.index]
                        if let snapshot = frameManager.snapshots[timestamp], let image = snapshot.image {
                            Image(image, scale: 1.0, label: Text("Screenshot"))
                                .resizable()
                                .scaledToFit()
//                                .overlay(
//                                    Group {
//                                        ForEach(ocrResults, id: \.uuid) { result in
//                                            OCRView(result.text, normalizedRect: result.normalizedRect)
//                                        }
//                                        .onAppear {
//                                            Task {
//                                                ocrResults = await getOCR(for: snapshot)
//                                            }
//                                        }
//                                    }
//                                    OCRGroup(snapshot: snapshot)
//                                    Group {
//                                        if let ocrResults = try? decodeOCR(data: snapshot.ocrData) {
//                                            ForEach(ocrResults, id: \.uuid) { result in
//                                                OCRView(
//                                                    result.text, normalizedRect: result.normalizedRect)
//                                            }
//                                        } else {
//                                            Text("\(snapshot)")
//                                        }
//                                    }
//                                )
                        } else {
                            Text("Failed to get the image")
                        }
                    } else {
                        Text("No images to display")
                    }

                    Spacer()

                    Button("Unregister") {
                        _ = LaunchManager.unregisterLoginItem()
                        _ = LaunchManager.unregisterLaunchAgent()
                    }
                }
            }
            .toolbar {
                Button("Previous", systemImage: "chevron.left", action: previousImage)
                    .disabled(frameManager.snapshots.isEmpty || frameManager.index < 1)

                Button("Next", systemImage: "chevron.right", action: nextImage)
                    .disabled(frameManager.snapshots.isEmpty || frameManager.index >= frameManager.snapshots.count)
                
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

                Spacer()

                Button("Info", systemImage: "info.circle", action: showInfo)
                    .disabled(frameManager.snapshots.isEmpty)
            }
            .toolbarBackground(backgroundColor)
        }
        .onAppear {
            _ = LaunchManager.registerLaunchAgent()
            xpcManager.setup()
            _ = LaunchManager.registerLoginItem()
            fetchImages()
        }
        .onDisappear {
            if let session = xpcManager.session {
                session.cancel(reason: "Done")
            }
        }
    }

    func previousImage() {
        frameManager.decrementIndex()
    }

    func nextImage() {
        frameManager.incrementIndex()
    }

    func showInfo() {
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
        }
    }

//    func decodeOCR(data jsonString: String) throws -> [OCRResult] {
//        guard let jsonData = jsonString.data(using: .utf8) else {
//            throw OCRError.error("Cannot decode json")
//        }
//        let decoder = JSONDecoder()
//        let results = try decoder.decode([OCRResult].self, from: jsonData)
//        return results
//    }
//
//    func getOCR(for snapshot: Snapshot) async -> [OCRResult] {
//        log("getOCR(\(snapshot.timestamp))")
//        if snapshot.ocrData.count > 0 {
//            var results: [OCRResult] = []
//
//            do {
//                results = try decodeOCR(data: snapshot.ocrData)
//            } catch {
//                print("decodeOCR error: \(error)")
//            }
//            return results
//        }
//
//        guard let image = snapshot.image else {
//            return []
//        }
//
//        let semaphore = DispatchSemaphore(value: 0)
//        var ocrData: String?
//        var results: [OCRResult] = []
//
//        do {
//            ocrData = try await performOCR(on: image)
//            if let ocrData = ocrData {
//                do {
//                    results = try decodeOCR(data: ocrData)
//                } catch {
//                    print("OCR error: \(error)")
//                }
//            }
//        } catch {
//            print("OCR error: \(error)")
//        }
//
//        return results
//    }
}
