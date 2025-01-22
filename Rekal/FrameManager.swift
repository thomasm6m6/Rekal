import Foundation
import AVFoundation

@MainActor
class FrameManager: ObservableObject {
    @Published var snapshots: [Snapshot] = []
    @Published var videos: [Video] = []
    @Published var index = 0
    @Published var isProcessing = false

    // TODO consider whether SQL JOIN function would be useful
    func extractFrames(date: Date, search: String = "") {
        snapshots = []
        videos = []
        index = 0

        let minTimestamp = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        let maxTimestamp = minTimestamp + 86400

        Task {
            do {
                let db = try Database()
                let tempDir = try Files.tempDir()
                videos = try db.videosBetween(minTime: minTimestamp, maxTime: maxTimestamp)
                
                isProcessing = true
                defer {
                    isProcessing = false
                }

                // TODO skip as much of this process as possible according to filters
                for video in videos {
                    var rawImages: [CGImage] = []
                    var snapshotsInVideo = try db.snapshotsInVideo(videoTimestamp: video.timestamp)
                    
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
                            case .success(requestedTime: _, let image, actualTime: _):
                                rawImages.append(image)
                            case .failure(requestedTime: let requested, let error):
                                print(
                                    "Failed to process image at \(requested.seconds) seconds for video '\(video.url.path)': '\(error)'"
                                )
                            }
                        }
                    } catch {
                        print("Error loading video: \(error)")
                    }
                    
                    guard snapshotsInVideo.count == rawImages.count else {
                        print("videoSnapshots.count != rawImages.count for \(video.url.path)")
                        continue
                    }
                    
                    // TODO proper fuzzy search
                    for (index, image) in rawImages.enumerated() {
                        snapshotsInVideo[index].image = image
                        let trimmedSearch = search.lowercased().trimmingCharacters(in: .whitespaces)
                        if trimmedSearch == "" {
                            snapshots.append(snapshotsInVideo[index])
                            continue
                        }
                        
                        let info = snapshotsInVideo[index].info
                        if trimmedSearch == info.appId.lowercased() {
                            snapshots.append(snapshotsInVideo[index])
                            continue
                        }
                        
                        if let name = info.appId.split(separator: ".").last,
                           trimmedSearch == name.lowercased()
                        {
                            snapshots.append(snapshotsInVideo[index])
                            continue
                        }
                        
                        if trimmedSearch
                            == info.appName.lowercased().trimmingCharacters(in: .whitespaces)
                        {
                            snapshots.append(snapshotsInVideo[index])
                            continue
                        }
                    }
                }
                try FileManager.default.removeItem(at: tempDir)
            } catch {
                print(error)
            }
        }
    }

    func incrementIndex() {
        if index < snapshots.count - 1 {
            index += 1
        }
    }

    func decrementIndex() {
        if index > 0 {
            index -= 1
        }
    }
}
