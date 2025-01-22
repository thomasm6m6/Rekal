import SwiftUI
import ServiceManagement

class XPCManager {
    var session: XPCSession?
    
    func setup() {
        print("here")
        session = try? XPCSession(machService: "com.thomasm6m6.RekalAgent.xpc")
    }
}

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

struct ContentView: View {
    @StateObject private var frameManager = FrameManager()
    @State private var selectedDate = Date()
    @State private var searchText = ""
    let xpcManager = XPCManager()
    
    @State var message = ""
    
    private let backgroundColor = Color(red: 18/256, green: 18/256, blue: 18/256) // #121212

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()
            
            NavigationStack {
                VStack {
                    
                    Spacer()

                    if !frameManager.snapshots.isEmpty {
                        let snapshot = frameManager.snapshots[frameManager.index]
                        if let image = snapshot.image {
                            Image(image, scale: 1.0, label: Text("Screenshot"))
                                .resizable()
                                .scaledToFit()
                                .overlay(
                                    Group {
                                        if let ocrResults = try? decodeOCR(data: snapshot.ocrData) {
                                            ForEach(ocrResults, id: \.uuid) { result in
                                                OCRView(
                                                    result.text, normalizedRect: result.normalizedRect)
                                            }
                                        } else {
                                            Text("\(snapshot)")
                                        }
                                    }
                                )
                        } else {
                            Text("Failed to get the image")
                        }
                    } else {
                        Text("No images to display")
                    }
                    
                    Text(message)
                    
                    Spacer()
                    
                    Button("Unregister") {
                        _ = LaunchManager.unregisterLoginItem()
                        _ = LaunchManager.unregisterLaunchAgent()
                    }
                    
                    Button("Get status") {
                        let loginItemStatus = LaunchManager.getLoginItemStatus()
                        let launchAgentStatus = LaunchManager.getLaunchAgentStatus()
                        message = "\(loginItemStatus), \(launchAgentStatus)"
                    }

                    Button("XPC StatusQuery RecordingStatus") {
                        guard let session = xpcManager.session else {
                            return
                        }

                        do {
                            let request = XPCRequest(messageType: .statusQuery(.recordingStatus))
                            let reply = try session.sendSync(request)
                            let response = try reply.decode(as: XPCResponse.self)
                            
                            DispatchQueue.main.async {
                                message = "Received response with result: \(response.reply)"
                            }
                        } catch {
                            message = "Failed to send message or decode reply: \(error)"
                        }
                    }

                    Button("XPC StatusQuery ImageCount") {
                        guard let session = xpcManager.session else {
                            return
                        }

                        do {
                            let request = XPCRequest(messageType: .statusQuery(.imageCount))
                            let reply = try session.sendSync(request)
                            let response = try reply.decode(as: XPCResponse.self)
                            
                            DispatchQueue.main.async {
                                message = "Received response with result: \(response.reply)"
                            }
                        } catch {
                            message = "Failed to send message or decode reply: \(error)"
                        }
                    }
                    
                    Spacer()
                }
            }
            .toolbar {
                Button("Previous image", systemImage: "chevron.left", action: previousImage)
                    .disabled(frameManager.snapshots.isEmpty)
                
                Button("Next image", systemImage: "chevron.right", action: nextImage)
                    .disabled(frameManager.snapshots.isEmpty)

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
            //        .toolbarColorScheme(.dark)
        }
        .onAppear {
            _ = LaunchManager.registerLoginItem()
            _ = LaunchManager.registerLaunchAgent()
            xpcManager.setup()
        }
    }
    
    func previousImage() {}
    
    func nextImage() {}
    
    func showInfo() {}
    
    enum OCRError: Error {
        case error(String)
    }

    func decodeOCR(data jsonString: String) throws -> [OCRResult] {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw OCRError.error("Cannot decode json")
        }
        let decoder = JSONDecoder()
        let results = try decoder.decode([OCRResult].self, from: jsonData)
        return results
    }
}
