import Foundation
import AVFoundation

enum ImageError: Error {
    case xpcError(String)
    case decodingError(String)
}

// TODO: don't do this
extension XPCSession: @unchecked @retroactive Sendable {}

// TODO: rename/restructure this. it applies to xpc more than to the images
actor ImageLoader {
    private var xpcSession: XPCSession?

    init() {
        do {
            xpcSession = try XPCSession(machService: "com.thomasm6m6.RekalAgent.xpc")
        } catch {
            print("Failed to initialize XPC session: \(error)")
        }
    }

    deinit {
        xpcSession?.cancel(reason: "Done")
    }

    func getImageCountFromXPC() async throws -> Int {
        guard let session = xpcSession else {
            throw ImageError.xpcError("No XPC session available")
        }

        let request = XPCRequest(messageType: .statusQuery(.imageCount))

        let response = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<XPCResponse, any Error>) in

            do {
                try session.send(request) { result in
                    switch result {
                    case .success(let reply):
                        do {
                            let response = try reply.decode(as: XPCResponse.self)
                            continuation.resume(returning: response)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        switch response.reply {
        case .imageCount(let count):
            return count
        case .error(let error):
            throw ImageError.xpcError("Error: \(error)")
        default:
            throw ImageError.xpcError("Unexpected reply")
        }
    }

    // TODO: abstract logic in this and the next function into a separate fn
    func processNow() async throws {
        guard let session = xpcSession else {
            throw ImageError.xpcError("No XPC session available")
        }

        let request = XPCRequest(messageType: .controlCommand(.processImages))

        let response = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<XPCResponse, any Error>) in

            do {
                try session.send(request) { result in
                    switch result {
                    case .success(let reply):
                        do {
                            let response = try reply.decode(as: XPCResponse.self)
                            continuation.resume(returning: response)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        switch response.reply {
        case .didProcess:
            log("Finished processing images")
        case .error(let error):
            log("Error processing images: \(error)")
        default:
            log("Unexpected reply")
        }
    }

    func loadImagesFromXPC() async throws -> [Snapshot] {
        guard let session = xpcSession else {
            throw ImageError.xpcError("No XPC session available")
        }

        let request = XPCRequest(messageType: .fetchImages)

        let response = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<XPCResponse, any Error>) in

            do {
                try session.send(request) { result in
                    switch result {
                    case .success(let reply):
                        do {
                            let response = try reply.decode(as: XPCResponse.self)
                            continuation.resume(returning: response)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        switch response.reply {
        case .snapshots(let encodedSnapshots):
            return decodeSnapshots(encodedSnapshots)
        default:
            throw ImageError.xpcError("Unexpected response")
        }
    }

    func getTimestampsFromXPC() async throws -> [Int: TimestampObject] {
        return [:]
    }
}

// TODO: load timestamps first so we can display the counter instantly
// TODO: get snapshots via XPC in chunks
@MainActor
class ImageModel: ObservableObject {
    @Published var snapshots: [Snapshot] = []
    @Published var index = 0
    @Published var displayCount = 0

    private let imageLoader = ImageLoader()

    func insert(snapshot: Snapshot) {
        let index = snapshots.firstIndex { $0.timestamp > snapshot.timestamp } ?? snapshots.count
        snapshots.insert(snapshot, at: index)
    }

    func setIndex(index: Int) {
        Task { self.index = index }
    }

    func processNow() {
        Task {
            do {
                try await imageLoader.processNow()
            } catch {
                log("Error processing")
            }
        }
    }

    func getTimestampsFromDisk() async throws -> [Int: TimestampObject] {
        let db = try Database()
        return try db.getTimestampList()
    }

    func loadImagesFromDisk(search: Search) async throws {
        let db = try Database()
        let videos = try db.videosBetween(minTime: search.minTimestamp, maxTime: search.maxTimestamp)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for video in videos {
                let snapshotsInVideo = try db.snapshotsInVideo(videoTimestamp: video.timestamp)
                group.addTask {
                    let frames = try await self.decodeVideo(url: video.url, snapshotsInVideo: snapshotsInVideo)
                    for snapshot in frames {
                        Task { @MainActor in
                            self.insert(snapshot: snapshot)
                        }
                    }
                }
            }
        }
    }

    private func decodeVideo(url: URL, snapshotsInVideo: [Snapshot]) async throws -> [Snapshot] {
        var rawImages: [CGImage] = []

        let asset = AVURLAsset(url: url)
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
                    print("Failed to process image at \(requested.seconds) seconds for video '\(url.path)': '\(error)'")
                }
            }
        } catch {
            print("Error loading video: \(error)")
        }

        guard snapshotsInVideo.count == rawImages.count else {
            throw ImageError.decodingError("snapshotsInVideo.count (\(snapshotsInVideo.count)) != rawImages.count (\(rawImages.count)) for \(url.path)")
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

    func loadImages(query: SearchQuery? = nil) {
        let searchText =
            if let query = query { query.text }
            else { "" }
        let search = Search.parse(text: searchText)

        snapshots = []

        Task {
            do {
                let imageCountXPC = try await imageLoader.getImageCountFromXPC()
                let imageCountDisk = try getImageCountFromDisk(
                    minTimestamp: search.minTimestamp,
                    maxTimestamp: search.maxTimestamp)

                self.displayCount = imageCountXPC + imageCountDisk

                let xpcSnapshots = try await imageLoader.loadImagesFromXPC()
                for snapshot in xpcSnapshots {
                    self.insert(snapshot: snapshot)
                }

                try await loadImagesFromDisk(search: search)
            } catch {
                print("Error loading images: \(error)")
            }
        }
    }

    func getImageCountFromDisk(minTimestamp: Int, maxTimestamp: Int) throws -> Int {
        do {
            let db = try Database()

            return try db.getImageCount(
                minTimestamp: minTimestamp,
                maxTimestamp: maxTimestamp)
        }
    }

    func nextImage() {
        Task {
            if !self.atLastImage {
                self.index += 1
            }
        }
    }

    func previousImage() {
        Task {
            if !self.atFirstImage {
                self.index -= 1
            }
        }
    }

    var atFirstImage: Bool {
        return index == 0
    }

    var atLastImage: Bool {
        return index == snapshots.count - 1
    }
}
