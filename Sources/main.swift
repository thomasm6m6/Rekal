import SwiftUI
import Foundation
import AVFoundation
import UniformTypeIdentifiers

// TODO don't block the UI while loading images
// TODO load full images
// TODO LiveText
// FIXME Viewer is pretty memory-heavy, e.g. 7.24gb for 4774 files (dec 27)
//       Memory usage continues increasing after it finishes loading images
//       Or maybe it just seems that way because of lazy loading?
// FIXME arrow keys still don't work

@MainActor
class VideoFrameManager: ObservableObject {
    @Published var images: [NSImage] = []
    @Published var videoIndex = 0
    @Published var videoCount = 0
    @Published var isProcessing = false

    func extractFrames(date: Date) {
        images = []

        // TODO use timestamps instead of Dates?
        // let dateMin = Calendar.current.startOfDay(for: date)
        // let dateMax = Calendar.current.date(byAdding: .day, value: 1, to: dateMin)!
        // var currentDate = dateMin
        let minTimestamp = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        let maxTimestamp = minTimestamp + 86400
        var timestamp = minTimestamp

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            print("Error creating directory: \(error)")
            return
        }

        Task {
            isProcessing = true
            // TODO struct
            var videoURLs: [URL] = []
            var timestamps: [Int] = []
            while timestamp < maxTimestamp {
                // print(timestamp)
                let videoURL = URL(fileURLWithPath: "/Users/tm/ss/small/\(timestamp).mp4")
                if !FileManager.default.isReadableFile(atPath: videoURL.path) {
                    timestamp += 300
                    continue
                }
                videoURLs.append(videoURL)
                timestamps.append(timestamp)
                timestamp += 300
                // print(videoURL)
            }
            // print(videoURLs)
            videoCount = videoURLs.count
            for videoURL in videoURLs {
                // print(videoURL)
                let timestamp = timestamps[videoIndex]
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
                process.arguments = [
                    "-nostdin",
                    "-v", "error",
                    "-i", videoURL.path,
                    "\(tempDir.path)/\(timestamp)-%04d.png"
                ]

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    print("Error: \(error)")
                }
                videoIndex += 1
            }
            do {
                let imageURLs = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension.lowercased() == "png" }
                    .sorted { $0.path < $1.path }
                images = imageURLs.compactMap { NSImage(contentsOf: $0) }
            } catch {
                print("Error: \(error)")
            }
            isProcessing = false
            do {
                try FileManager.default.removeItem(at: tempDir)
            } catch {
                print("Error: \(error)")
            }
        }
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
            ImageView(images: frameManager.images, videoIndex: frameManager.videoIndex, videoCount: frameManager.videoCount)
                .defaultFocus($focusedArea, .imageViewer, priority: .userInitiated)
        }
        .onAppear {
            focusedArea = .imageViewer
        }
    }
}

struct ImageView: View {
    let images: [NSImage]
    let videoIndex: Int
    let videoCount: Int
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
                Spacer()
                Text("No images available")
            }

            Spacer()
            
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

                Text("\(videoIndex)/\(videoCount)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("\(currentIndex)/\(images.count)")
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