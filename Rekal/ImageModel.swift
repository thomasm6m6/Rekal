import Foundation
import AVFoundation
import OrderedCollections

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

    func loadImagesFromXPC() async throws -> SnapshotList {
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

@MainActor
class ImageModel: ObservableObject {
//    @Published var snapshots = SnapshotList()
    @Published var snapshots: [Snapshot] = []
    @Published var index = 0

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
            for (_, video) in videos {
                let snapshotsInVideo = try db.snapshotsInVideo(videoTimestamp: video.timestamp)
                group.addTask {
                    let frames = try await self.decodeVideo(video: video, snapshotsInVideo: snapshotsInVideo)
                    for (timestamp, snapshot) in frames {
                        Task { @MainActor in
                            self.insert(snapshot: snapshot)
                        }
                    }
                }
            }
        }
    }

    private func decodeVideo(video: Video, snapshotsInVideo: SnapshotList) async throws -> SnapshotList {
        var rawImages: [CGImage] = []

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
                    print("Failed to process image at \(requested.seconds) seconds for video '\(video.url.path)': '\(error)'")
                }
            }
        } catch {
            print("Error loading video: \(error)")
        }

        guard snapshotsInVideo.count == rawImages.count else {
            throw ImageError.decodingError("snapshotsInVideo.count (\(snapshotsInVideo.count)) != rawImages.count (\(rawImages.count)) for \(video.url.path)")
        }

        var result = SnapshotList()

        // TODO: proper fuzzy search
        for (index, image) in rawImages.enumerated() {
            let timestamp = snapshotsInVideo.keys[index]
            guard var snapshot = snapshotsInVideo[timestamp] else {
                continue
            }
            snapshot.image = image

            result[timestamp] = snapshot
        }

        return result
    }

    // TODO figure out whether it actually helps to offload images
//    func loadImages(search searchText: String = "") {
//        Task {
//            do {
//                let db = try Database()
//                var timestamps = try await imageLoader.getTimestampsFromXPC()
//                let diskTimestamps = try await imageLoader.getTimestampsFromDisk()
//
//                var videoTimestamps: [Int] = []
//
//                timestamps.merge(diskTimestamps) { old, new in return new }
//                let timestampList = timestamps.sorted(by: { $0.0 < $1.0 })
//                for (timestamp, object) in timestampList[0..<100] {
//                    switch object.source {
//                    case .xpc:
//                        print("todo")
//                    case .disk(let videoTimestamp):
//                        if !videoTimestamps.contains(videoTimestamp) {
//                            videoTimestamps.append(videoTimestamp)
//                        }
//                    }
//                }
//
//                var resultSnapshots = SnapshotList()
//
//                try await withThrowingTaskGroup(of: SnapshotList.self) { group in
//                    for timestamp in videoTimestamps {
//                        let snapshotsInVideo = try db.snapshotsInVideo(videoTimestamp: timestamp)
//                        let url = try db.getVideoURL(for: timestamp)
//                        group.addTask {
//                            return try await decodeVideo(url: url, snapshotsInVideo: snapshotsInVideo)
//                        }
//
//                        for try await snapshotList in group {
//                            for (timestamp, snapshot) in snapshotList {
//                                self.snapshots[timestamp] = snapshot
////                                resultSnapshots[timestamp] = snapshot
//                            }
//                        }
//                    }
//                }

//                for (timestamp, snapshot) in resultSnapshots {
//                    if self.snapshots[timestamp] == nil {
//                        self.snapshots[timestamp] = snapshot
//                    }
//                }
//            } catch {
//                log("Error: \(error)")
//            }
//        }

        func decodeVideo(url: URL, snapshotsInVideo: SnapshotList) async throws -> SnapshotList {
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

            var result = SnapshotList()

            // TODO: proper fuzzy search
            for (index, image) in rawImages.enumerated() {
                let timestamp = snapshotsInVideo.keys[index]
                guard var snapshot = snapshotsInVideo[timestamp] else {
                    continue
                }
                snapshot.image = image

                result[timestamp] = snapshot
            }

            return result
        }

        // Get list of timestamps from daemon and from database
        // Support filters in the getTimestamps functions to support search
        // Pick e.g. 100 of these timestamps, maybe index +- 50 (or +100 if index==0, etc) and load the images for them.
        // When index changes, load a new image and drop an image (actually will do this in batches bc both db and xpc work better that way)

//        loadImagesFromXPC()
//
//        let search = Search.parse(text: searchText)
//        loadImagesFromDisk(search: search)
//    }

    // FIXME: loads images out of order
    func loadImages(searchText: String = "") {
        Task {
            do {
                // Load from XPC
                let xpcSnapshots = try await imageLoader.loadImagesFromXPC()
                for (timestamp, snapshot) in xpcSnapshots {
                    self.insert(snapshot: snapshot)
                }

                // Load from disk
                let search = Search.parse(text: searchText)
                try await loadImagesFromDisk(search: search)
            } catch {
                print("Error loading images: \(error)")
            }
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
