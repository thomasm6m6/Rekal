import SwiftUI
import Foundation
import AVFoundation
import Common

// TODO don't block the UI while loading images
// TODO load full images
// FIXME Viewer is pretty memory-heavy, e.g. 7.24gb for 4774 files (dec 27)
//       Memory usage continues increasing after it finishes loading images
//       Or maybe it just seems that way because of lazy loading?
// TODO arrow keys and media keys
// TODO export image
// TODO zoom
// TODO slider for granularity using similarity percentage via hashing

// TODO XPC/EventKit
// TODO menu bar icon to pause/resume recording
// TODO button to force processing regardless of battery state
// TODO holding arrow buttons scrubs in that direction

@MainActor
class VideoFrameManager: ObservableObject {
    @Published var images: [CGImage] = []
    @Published var videos: [Video] = []
    @Published var index = 0
    @Published var isProcessing = false

    // TODO consider whether SQL JOIN function would be useful
    func extractFrames(date: Date) {
        images = []
        videos = []
        index = 0

        let minTimestamp = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        let maxTimestamp = minTimestamp + 86400

        do {
            let db = try Database()
            let tempDir = try Files.tempDir()
            videos = try db.videosBetween(minTime: minTimestamp, maxTime: maxTimestamp)

            Task {
                isProcessing = true
                for video in videos {
                    let asset = AVURLAsset(url: video.url)
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.requestedTimeToleranceBefore = .zero
                    generator.requestedTimeToleranceAfter = .zero

                    do {
                        let duration = try await asset.load(.duration)
                        let times = stride(from: 1.0, to: duration.seconds, by: 1.0).map {
                            CMTime(seconds: $0, preferredTimescale: duration.timescale)
                        }

                        for await result in generator.images(for: times) {
                            switch result {
                            case .success(requestedTime: _, image: let image, actualTime: _):
                                self.images.append(image)
                            case .failure(requestedTime: let requested, error: let error):
                                print("Failed to process image at \(requested.seconds) seconds for video '\(video.url.path)': '\(error)'")
                            }
                        }
                    } catch {
                        print("Error loading video: \(error)")
                    }
                }
                isProcessing = false
                try FileManager.default.removeItem(at: tempDir)
            }
        } catch {
            print(error)
        }
    }

    func incrementIndex() {
        if index < images.count - 1 {
            index += 1
        }
    }

    func decrementIndex() {
        if index > 0 {
            index -= 1
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
            ImageView(frameManager: frameManager)
        }
    }
}

struct ImageView: View {
    let frameManager: VideoFrameManager
    @State private var currentIndex = 0
    @State private var isPlaying = false
    
    let timer = Timer.publish(every: 0.025, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            if !frameManager.images.isEmpty {
                Image(frameManager.images[frameManager.index], scale: 1.0, label: Text("Screenshot"))
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
                .disabled(isPlaying || frameManager.index <= 0)

                Spacer()

                Button(action: { isPlaying.toggle() }) {
                    Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                        .imageScale(.large)
                }
                .disabled(frameManager.images.isEmpty || frameManager.index >= frameManager.images.count - 1)

                Text("\(frameManager.images.count == 0 ? 0 : frameManager.index+1)/\(frameManager.images.count) frames")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: nextImage) {
                    Image(systemName: "arrow.right")
                }
                .disabled(isPlaying || frameManager.index >= frameManager.images.count - 1)
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
        frameManager.decrementIndex()
    }

    private func nextImage() {
        frameManager.incrementIndex()
        if frameManager.index == frameManager.images.count - 1 && isPlaying {
            isPlaying = false
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