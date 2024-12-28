import SwiftUI
import Foundation
import AVFoundation
import UniformTypeIdentifiers

// Video frame extraction service
class VideoFrameExtractor {
    static func extractFrames2(date: Date) throws {
        // Convert date to filename format (assuming filename is Unix timestamp)
        let timestamp = Int(date.timeIntervalSince1970)
        let videoURL = URL(fileURLWithPath: "/Users/tm/ss/small/\(timestamp).mp4")
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        print("Using temp dir: \(tempDir.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = [
            "-nostdin",
            "-v", "error",
            "-i", videoURL.path,
            "\(tempDir.path)/frame-%04d.png"
        ]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("FFmpeg failed: \(error)")
        }
    }

    // static func extractFrames(from videoURL: URL) async throws -> [CGImage] {
    //     let asset = AVAsset(url: videoURL)
    //     let generator = AVAssetImageGenerator(asset: asset)
    //     generator.appliesPreferredTrackTransform = true
        
    //     // Get video duration and calculate frame times
    //     let duration = try await asset.load(.duration)
    //     let seconds = duration.seconds
    //     let frameRate = 20.0
    //     let times = stride(from: 0.0, to: seconds, by: frameRate).map {
    //         CMTime(seconds: $0, preferredTimescale: 600)
    //     }

    //     var images: [CGImage] = []

    //     // Extract frames
    //     for time in times {
    //         do {
    //             let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
    //             images.append(cgImage)
    //         } catch {
    //             print("Failed to extract frame at time \(time): \(error)")
    //         }
    //     }
        
    //     return images
    // }
}

@MainActor
class VideoFrameManager: ObservableObject {
    @Published var images: [NSImage] = []
    @Published var isProcessing = false
    
    func extractFrames(date: Date) {
        Task {
            isProcessing = true
            do {
                let tempDir = try await VideoFrameManager.extractFrames2(date: date)
                let imageURLs = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension.lowercased() == "png" }
                    .sorted { $0.path < $1.path }
                
                let loadedImages = imageURLs.compactMap { NSImage(contentsOf: $0) }
                
                self.images = loadedImages
                self.isProcessing = false
            } catch {
                print("Error: \(error)")
                self.isProcessing = false
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
            ImageGridView(images: frameManager.images)
        }
    }
}

struct ImageGridView: View {
    let images: [NSImage]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 150)
                }
            }
            .padding()
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