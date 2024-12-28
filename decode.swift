import Foundation
import AVFoundation
import UniformTypeIdentifiers
import Dispatch

class VideoFrameDecoder {
    static func decodeFirstVideo2() async throws {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let ssDir = homeDir.appendingPathComponent("ss")

        guard FileManager.default.fileExists(atPath: ssDir.path) else {
            throw NSError(domain: "VideoDecoder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Directory ~/ss does not exist"])
        }

        // let videos = try FileManager.default.contentsOfDirectory(at: ssDir, includingPropertiesForKeys: [.contentTypeKey])
        //     .filter { url in
        //         if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
        //         let contentType = resourceValues.contentType {
        //             return contentType.conforms(to: .movie)
        //         }
        //         return false
        //     }
        //     .sorted { $0.lastPathComponent < $1.lastPathComponent }

        // guard let firstVideo = videos.first else {
        //     throw NSError(domain: "VideoDecoder", code: 2, userInfo: [NSLocalizedDescriptionKey: "No video files found in ~/ss"])
        // }

        // let firstVideo = ssDir.appendingPathComponent("1735070400.mp4") // smallest file
        // let firstVideo = ssDir.appendingPathComponent("1735142400.mp4") // biggest file
        // let firstVideo = ssDir.appendingPathComponent("1735292100.mp4")
        let firstVideo = URL(fileURLWithPath: "/Users/tm/ss/small/1735152000.mp4")

        print("Processing video: \(firstVideo.path)")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        print("Using temp dir: \(tempDir.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = [
            "-nostdin",
            "-v", "error",
            // "-skip_frame", "nokey",
            // "-skip_frame", "nointra",
            "-i", firstVideo.path,
            // "-r", "0.1",
            // "-vf", "fps=1,select=not(mod(n\\,10))",
            // "-r", "0.1", "-vf", "fps=1",
            "\(tempDir.path)/frame-%04d.png"
        ]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("FFmpeg failed: \(error)")
        }
    }

    static func decodeFirstVideo() async throws {
        // Get first MP4 file
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let ssDir = homeDir.appendingPathComponent("ss")
        
        guard FileManager.default.fileExists(atPath: ssDir.path) else {
            throw NSError(domain: "VideoDecoder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Directory ~/ss does not exist"])
        }
        
        // let videos = try FileManager.default.contentsOfDirectory(at: ssDir, includingPropertiesForKeys: [.contentTypeKey])
        //     .filter { url in
        //         if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
        //            let contentType = resourceValues.contentType {
        //             return contentType.conforms(to: .movie)
        //         }
        //         return false
        //     }
        //     .sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        // guard let firstVideo = videos.first else {
        //     throw NSError(domain: "VideoDecoder", code: 2, userInfo: [NSLocalizedDescriptionKey: "No video files found in ~/ss"])
        // }
        
        let firstVideo = ssDir.appendingPathComponent("1735293900.mp4")

        guard FileManager.default.isReadableFile(atPath: firstVideo.path) else {
            throw NSError(domain: "VideoDecoder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot read video file: \(firstVideo.path)"])
        }
        
        print("Processing video: \(firstVideo.path)")
        
        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        print("Using temp dir: \(tempDir.path)")
        
        // Setup video asset
        let asset = AVURLAsset(url: firstVideo)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        let duration = try await asset.load(.duration)
        // TODO rethink the timescale and framerate
        let frameRate = 1.0
        let timescale = try await asset.loadTracks(withMediaType: .video).first?.load(.naturalTimeScale) ?? 600
        let times = stride(from: 0.0, to: duration.seconds, by: 1.0/frameRate).map {
            CMTime(seconds: $0, preferredTimescale: timescale)
        }

        for await result in generator.images(for: times) {
            switch result {
            case .success(requestedTime: _, image: let image, actualTime: let actual):
                let frameURL = tempDir.appendingPathComponent("frame-\(actual.value).png")
                let dest = CGImageDestinationCreateWithURL(frameURL as CFURL, UTType.png.identifier as CFString, 1, nil)
                
                if let dest = dest {
                    CGImageDestinationAddImage(dest, image, nil)
                    CGImageDestinationFinalize(dest)
                }
            case .failure(requestedTime: let requested, error: let error):
                print("Error: \(error) at requested time \(requested)")
            }
        }
    }
}

let semaphore = DispatchSemaphore(value: 0)

Task {
    do {
        try await VideoFrameDecoder.decodeFirstVideo2()
    } catch {
        print("Error: \(error.localizedDescription)")
    }
    semaphore.signal()
}

semaphore.wait()