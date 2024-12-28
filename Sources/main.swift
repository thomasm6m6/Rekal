import SwiftUI
import Foundation
import AVFoundation
import UniformTypeIdentifiers

// Video frame extraction service
class VideoFrameExtractor {
    static func extractFrames(from videoURL: URL) async throws -> [CGImage] {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        // Get video duration and calculate frame times
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        let frameRate = 20.0
        let times = stride(from: 0.0, to: seconds, by: frameRate).map {
            CMTime(seconds: $0, preferredTimescale: 600)
        }
        
        var images: [CGImage] = []
        
        // Extract frames
        for time in times {
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                images.append(cgImage)
            } catch {
                print("Failed to extract frame at time \(time): \(error)")
            }
        }
        
        return images
    }
}

struct MainView: View {
    @State private var selectedDate = Date()

    var body: some View {
        NavigationSplitView {
            VStack {
                Text("Select a Date")
                    .font(.headline)

                DatePicker("",
                           selection: $selectedDate,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)

                Text("Selected Date:")
                Text("\(selectedDate.formatted())")

                Spacer()
            }
            // .padding()
            // .frame(minWidth: 200)

        } detail: {
            ImageGridView() // or pass selectedDate if needed
        }
    }
}

struct ImageGridView: View {
    @State private var images: [NSImage] = []
    @State private var isExtracting = false
    @State private var currentIndex = 0
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack {
            if isExtracting {
                ProgressView("Extracting frames...")
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 150))
                    ], spacing: 10) {
                        ForEach(images.indices, id: \.self) { index in
                            Image(nsImage: images[index])
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 150)
                        }
                    }
                    .padding()
                }
            }
            
            Button("Select Video") {
                selectVideo()
            }
        }
    }
    
    private func selectVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.movie]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            isExtracting = true
            
            Task {
                do {
                    let cgImages = try await VideoFrameExtractor.extractFrames(from: url)
                    await MainActor.run {
                        images = cgImages.map { NSImage(cgImage: $0, size: .zero) }
                        isExtracting = false
                    }
                } catch {
                    print("Error extracting frames: \(error)")
                    await MainActor.run {
                        isExtracting = false
                    }
                }
            }
        }
    }
}

@main
struct Rekal: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
