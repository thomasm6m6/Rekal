import SwiftUI
import Foundation
import AVFoundation
import UniformTypeIdentifiers

// FIXME I don't think it's loading images exactly in chronological order. Issue might just be the one below.
// FIXME it's definitely loading some chunks multiple times
// TODO don't block the UI on loading images
// TODO load full images
// TODO LiveText
// FIXME viewer is *very* memory heavy. on the order of ~10gb. Oddly, memory usage continues increasing after it finishes loading images(?)
//       or maybe it just seems that way because of lazy loading?

@MainActor
class VideoFrameManager: ObservableObject {
    @Published var images: [NSImage] = []
    @Published var isProcessing = false

    func extractFrames(date: Date) {
        let date0 = date
        var date1 = date
        Task {
            isProcessing = true
            while true {
                do {
                    let tempDir = try await VideoFrameManager.extractFrames2(date: date1)
                    let imageURLs = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                        .filter { $0.pathExtension.lowercased() == "png" }
                        .sorted { $0.path < $1.path }
                    
                    let loadedImages = imageURLs.compactMap { NSImage(contentsOf: $0) }
                    
                    self.images += loadedImages
                    // self.isProcessing = false
                } catch {
                    print("Error: \(error)")
                    // self.isProcessing = false
                }
                date1 = date1.addingTimeInterval(5 * 60)
                if Calendar.current.ordinality(of: .day, in: .year, for: date1) ?? 0 > Calendar.current.ordinality(of: .day, in: .year, for: date0) ?? 0 {
                    // FIXME time zones are mixed up I think
                    self.isProcessing = false
                    break
                }
            }
        }
    }

    static func extractFrames2(date: Date) async throws -> URL {
        let origTimestamp = Int(date.timeIntervalSince1970)
        let minTimestamp = origTimestamp / 300 * 300
        let maxTimestamp = minTimestamp + 86400

        var timestamp = minTimestamp
        while true {
            let videoURL = URL(fileURLWithPath: "/Users/tm/ss/small/\(timestamp).mp4")
            if FileManager.default.isReadableFile(atPath: videoURL.path) {
                break
            }
            if timestamp == maxTimestamp {
                break
            }
            timestamp += 300
        }
        guard timestamp != maxTimestamp else {
            throw NSError(domain: "VideoDecoder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot find file"])
        }
        let videoURL = URL(fileURLWithPath: "/Users/tm/ss/small/\(timestamp).mp4")
        guard FileManager.default.isReadableFile(atPath: videoURL.path) else {
            throw NSError(domain: "VideoDecoder", code: 4, userInfo: [NSLocalizedDescriptionKey: "Still cannot find file"])
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = [
            "-nostdin",
            "-v", "error",
            "-i", videoURL.path,
            "\(tempDir.path)/frame-%04d.png"
        ]
        
        try process.run()
        process.waitUntilExit()
        
        return tempDir
    }
}

struct MainView: View {
    @StateObject private var frameManager = VideoFrameManager()
    @State private var selectedDate = Date()
    @Namespace var namespace
    @FocusState private var focusedArea: FocusArea?
    
    enum FocusArea {
        case sidebar
        case imageViewer
    }
    
    var body: some View {
        NavigationSplitView {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .focusable(false)
                .allowsHitTesting(true)
                
                Button("Extract Frames") {
                    frameManager.extractFrames(date: selectedDate)
                }
                .disabled(frameManager.isProcessing)
                .focusable(false)
                
                if frameManager.isProcessing {
                    ProgressView("Processing...")
                }
                
                Spacer()
            }
        } detail: {
            ImageView(images: frameManager.images)
                .defaultFocus($focusedArea, .imageViewer, priority: .userInitiated)
        }
        .onAppear {
            focusedArea = .imageViewer
        }
    }
}

struct ImageView: View {
    let images: [NSImage]
    @State private var currentIndex = 0
    @State private var isPlaying = false
    @FocusState private var isFocused: Bool
    
    let timer = Timer.publish(every: 0.025, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack {
            if (!images.isEmpty) {
                Image(nsImage: images[currentIndex])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("No images available")
            }
            
            HStack {
                Button(action: previousImage) {
                    Image(systemName: "arrow.left")
                }
                .disabled(currentIndex <= 0)
                
                Spacer()
                
                Button(action: { isPlaying.toggle() }) {
                    Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                        .imageScale(.large)
                }
                .disabled(images.isEmpty || currentIndex >= images.count - 1)

                Text("\(currentIndex + 1)/\(images.count)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: nextImage) {
                    Image(systemName: "arrow.right")
                }
                .disabled(currentIndex >= images.count - 1)
            }
            .padding()
        }
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.leftArrow) { previousImage(); return .handled }
        .onKeyPress(.rightArrow) { nextImage(); return .handled }
        .onReceive(timer) { _ in
            if isPlaying {
                nextImage()
            }
        }
    }
    
    private func previousImage() {
        if currentIndex > 0 {
            currentIndex -= 1
        }
    }
    
    private func nextImage() {
        if currentIndex < images.count - 1 {
            currentIndex += 1
        } else {
            if isPlaying {
                isPlaying = false
            }
        }
    }
}

@main
struct Rekal: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}