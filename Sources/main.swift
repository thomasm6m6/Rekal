import SwiftUI
import Foundation

// FIXME left/right keys don't work

struct ImageGridView: View {
    @State private var images: [URL] = []
    @State private var tempDir: URL?
    @State private var isExtracting = false
    @State private var currentIndex = 0
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack {
            Button(action: {
                isExtracting = true
                extractFrames()
            }) {
                Text("Extract Frames")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(isExtracting)
            
            if isExtracting && !images.isEmpty {
                HStack {
                    Button(action: previousImage) {
                        Image(systemName: "chevron.left")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                    .disabled(currentIndex <= 0)
                    .padding()
                    
                    Spacer()
                    
                    if let image = NSImage(contentsOf: images[currentIndex]) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    Spacer()
                    
                    Button(action: nextImage) {
                        Image(systemName: "chevron.right")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                    .disabled(currentIndex >= images.count - 1)
                    .padding()
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.leftArrow) {
            previousImage()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            nextImage()
            return .handled
        }
    }
    
    private func nextImage() {
        if currentIndex < images.count - 1 {
            currentIndex += 1
        }
    }
    
    private func previousImage() {
        if currentIndex > 0 {
            currentIndex -= 1
        }
    }
    
    func extractFrames() {
        // Create temp directory
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        tempDir = temp
        
        // Get first mp4
        let ssDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ss")
        guard let videoURL = try? FileManager.default.contentsOfDirectory(at: ssDir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "mp4" }) else { return }

        print(videoURL.path)

        // Extract frames using ffmpeg
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = [
            "-nostdin",
            "-i", videoURL.path,
            "-vf", "fps=20",
            "\(temp.path)/frame-%04d.png"
        ]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("ffmpeg failed: \(error)")
        }
        
        // Load extracted images
        images = (try? FileManager.default.contentsOfDirectory(
            at: temp,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "png" }
        .sorted { $0.path < $1.path }) ?? []
    }
}

@main
struct FrameViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ImageGridView()
        }
    }
}
