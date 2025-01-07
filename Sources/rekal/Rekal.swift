import SwiftUI
import Foundation
import AVFoundation
import UniformTypeIdentifiers // XXX necessary?
import Common

// TODO don't block the UI while loading images
// TODO load full images
// TODO LiveText
// FIXME Viewer is pretty memory-heavy, e.g. 7.24gb for 4774 files (dec 27)
//       Memory usage continues increasing after it finishes loading images
//       Or maybe it just seems that way because of lazy loading?
// TODO arrow keys and media keys
// TODO export image
// TODO zoom
// FIXME currentIndex is not updated when loadImages is called
// TODO slider for granularity using similarity percentage via hashing

// TODO XPC/EventKit
// TODO ramdisk/api for decoding?
// TODO menu bar icon to pause/resume recording
// TODO button to force processing regardless of battery state

@MainActor
class VideoFrameManager: ObservableObject {
    @Published var images: [NSImage] = []
    @Published var videos: [Video] = []
    @Published var videoIndex = 0
    @Published var isProcessing = false

    // TODO consider whether SQL JOIN function would be useful
    func extractFrames(date: Date) {
        images = []
        videos = []
        videoIndex = 0

        let minTimestamp = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        let maxTimestamp = minTimestamp + 86400

        do {
            let db = try Database()
            let tempDir = try Files.tempDir()
            videos = try db.videosBetween(minTime: minTimestamp, maxTime: maxTimestamp)        
            print(videos)

            Task {
                isProcessing = true
                for video in videos {
                    print(video)

                    let process = Process()
                    process.executableURL = URL(filePath: "/opt/homebrew/bin/ffmpeg")
                    process.arguments = [
                        "-nostdin",
                        "-v", "error",
                        "-i", video.url.path,
                        "\(tempDir.path)/\(video.timestamp)-%04d.png"
                    ]
                    print(process.arguments ?? "")

                    do {
                        try process.run()
                        process.waitUntilExit()

                        videoIndex += 1

                        // TODO don't get the image URLs this way--we have frameCount so can calculate manually
                        let imageURLs = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                            .filter { $0.pathExtension.lowercased() == "png" }
                            .sorted { $0.path < $1.path }
                        images = imageURLs.compactMap { NSImage(contentsOf: $0) }
                    } catch {
                        print(error)
                    }
                }
                isProcessing = false
                try FileManager.default.removeItem(at: tempDir)
            }
        } catch {
            print(error)
        }
    }
}

struct MainView: View {
    @StateObject private var frameManager = VideoFrameManager()
    @State private var selectedDate = Date()
    @Namespace var namespace

    var body: some View {
        NavigationSplitView {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)

                Button("Extract Frames") {
                    frameManager.extractFrames(date: selectedDate)
                }
                .disabled(frameManager.isProcessing)

                if frameManager.isProcessing {
                    ProgressView("Processing...")
                }

                Spacer()
            }
        } detail: {
            ImageView(images: frameManager.images, videos: frameManager.videos, videoIndex: frameManager.videoIndex)
        }
    }
}

struct ImageView: View {
    let images: [NSImage]
    let videos: [Video]
    let videoIndex: Int
    @State private var currentIndex = 0
    @State private var isPlaying = false
    
    let timer = Timer.publish(every: 0.025, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            if !images.isEmpty {
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
                .disabled(isPlaying || currentIndex <= 0)

                Spacer()

                Text("\(videoIndex)/\(videos.count) videos")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)

                Button(action: { isPlaying.toggle() }) {
                    Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                        .imageScale(.large)
                }
                .disabled(images.isEmpty || currentIndex >= images.count - 1)

                Text("\(currentIndex)/\(images.count) frames")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: nextImage) {
                    Image(systemName: "arrow.right")
                }
                .disabled(isPlaying || currentIndex >= images.count - 1)
            }
            .padding()
        }
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