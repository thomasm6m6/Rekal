import Foundation
import AVFoundation

log2("Decoder a")
// Set up the listener and start listening for connections.
startListener()
log2("Decoder b")

// Create the listener that receives incoming session requests from clients.
func startListener() {
    do {
        _ = try XPCListener(service: "com.thomasm6m6.RekalDecoder") { request in
            request.accept { message in
                return performTask(with: message)
            }
        }

        log2("Started XPC Service...")

        // Start the main dispatch queue to begin processing messages.
        dispatchMain()
    } catch {
        log2("Failed to create listener, error: \(error)")
    }
}

func performTask(with message: XPCReceivedMessage) -> Encodable? {
    do {
        let request = try message.decode(as: DecodeRequest.self)
        if let action = request.action, action == .quit {
            exit(0)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: DecodeResponse?

        Task {
            do {
                let snapshots = try await decodeVideo(timestamp: request.timestamp, url: request.url)
                let encodedSnapshots = encodeSnapshots(snapshots)
                result = DecodeResponse(snapshots: encodedSnapshots)
            } catch {
                log2("XPC Service error: \(error)")
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    } catch {
        log2("XPC Service: Failed to decode received message, error: \(error)")
        return nil
    }
}

func decodeVideo(timestamp: Int, url: URL) async throws -> [Snapshot] {
    let db = try Database()
    let snapshotsInVideo = try db.snapshotsInVideo(videoTimestamp: timestamp)

    var rawImages: [CGImage] = []
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    let duration = try await asset.load(.duration)
    let times = stride(from: 1.0, to: duration.seconds, by: 1.0).map {
        CMTime(seconds: $0, preferredTimescale: duration.timescale)
    }

    for await result in generator.images(for: times) {
        switch result {
        case .success(_, let image, _):
            rawImages.append(image)
        case .failure(let requested, let error):
            log2("XPC Service: Failed at \(requested.seconds): \(error.localizedDescription)")
        }
    }

    guard snapshotsInVideo.count == rawImages.count else {
        throw XPCDecodingError.error("snapshotsInVideo.count (\(snapshotsInVideo.count)) != rawImages.count (\(rawImages.count)) for \(url.path)")
    }

    var result: [Snapshot] = []

    // TODO: proper fuzzy search
    for (index, image) in rawImages.enumerated() {
        let timestamp = snapshotsInVideo[index].timestamp
        guard var snapshot = snapshotsInVideo.first(where: { $0.timestamp == timestamp }) else {
            continue
        }
        snapshot.image = image

        result.append(snapshot)
    }

    return result
}
