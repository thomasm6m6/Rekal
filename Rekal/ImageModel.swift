import Foundation
import AVFoundation

enum ImageError: Error {
    case xpcError(String)
    case decodingError(String)
}

// TODO: don't do this
extension XPCSession: @unchecked @retroactive Sendable {}

// TODO: rename/restructure this. it applies to xpc more than to the images
// Does ImageLoader need to be an actor?
actor ImageLoader {
    private var xpcSession: XPCSession?

    init() {}

    deinit {
        xpcSession?.cancel(reason: "Done")
    }

    func activate() {
        do {
            xpcSession = try XPCSession(
                machService: "com.thomasm6m6.RekalAgent.xpc"
                // TODO: would like to use options: .inactive, but can't solve the concurrency error
                // solution is probably either nonisolated(unsafe) or to run on main actor
            )
        } catch {
            print("Failed to initialize XPC session: \(error.localizedDescription)")
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

    // FIXME: not loading from XPC
    func loadImagesFromXPC(timestamps: TimestampList) async throws -> [Snapshot] {
        guard timestamps.count > 0 else { return [] }
        guard let session = xpcSession else {
            throw ImageError.xpcError("No XPC session available")
        }

        // FIXME: ignoring search parameters. should use the timestamps passed as argument (also fix in loadImagesFromDisk)
        let request = XPCRequest(messageType: .fetchImagesFromRange(minTimestamp: timestamps.block, maxTimestamp: timestamps.block + 300))
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

    func getTimestamps(from minTimestamp: Int, to maxTimestamp: Int) async throws -> [TimestampList] {
        guard let session = xpcSession else {
            throw ImageError.xpcError("No XPC session available")
        }

        let request = XPCRequest(messageType: .getTimestampBlocks(min: minTimestamp, max: maxTimestamp))
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
        case .timestampBlocks(let timestamps):
            return timestamps
        default:
            throw ImageError.xpcError("Unexpected response")
        }
    }
}

// TODO: load timestamps first so we can display the counter instantly
// TODO: get snapshots via XPC in chunks
@MainActor
class ImageModel: ObservableObject {
    @Published var snapshots: [Snapshot] = [] // loaded snapshots
    @Published var timestamps: [TimestampList] = [] // all timestamps matching current search
    @Published var index = 0 // index within `snapshots`
    @Published var timestampIndex = 0 // index within `timestamps`
    @Published var snapshotCount = 0 // total number of snapshots
    @Published var totalIndex = 0 // index from [0, snapshotCount)

    private let imageLoader = ImageLoader()
    private var isLoading = false
    private var lastQuery: SearchQuery? = nil

    private let arraySize = 60
    private let arrayOffset = 20

    func activate() {
        Task { await imageLoader.activate() }
    }

    func insert(snapshot: Snapshot) {
        let index = snapshots.firstIndex { $0.timestamp > snapshot.timestamp } ?? snapshots.count
        snapshots.insert(snapshot, at: index)
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

    // TODO: probably want to accept a callback instead and run that every time we have an image, so that we can display images faster
    func loadImagesFromDisk(timestamps: TimestampList) async throws -> [Snapshot] {
        guard timestamps.count > 0 else { return [] }
        let db = try Database()
        let videos = try db.getVideosBetween(minTimestamp: timestamps.block, maxTimestamp: timestamps.block + 300)
        guard videos.count > 0 else { return [] }

        let session = try XPCSession(xpcService: "com.thomasm6m6.RekalDecoder")
        defer { session.cancel(reason: "Done") }

        var loadedSnapshots: [Snapshot] = []
        for video in videos {
            let frames = try await self.decodeVideo(video: video, session: session)
            for snapshot in frames {
                loadedSnapshots.append(snapshot)
            }
        }
        return loadedSnapshots
    }

    func decodeVideo(video: Video, session: XPCSession) async throws -> [Snapshot] {
        let request = DecodeRequest(url: video.url, timestamp: video.timestamp, action: nil)
        let response = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<DecodeResponse, any Error>) in

            Task.detached {
                do {
                    try session.send(request) { (result: Result<DecodeResponse, any Error>) in
                        switch result {
                        case .success(let response):
                            continuation.resume(returning: response)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                } catch {
                    log2("Error sending request: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }

        let decodedSnapshots = decodeSnapshots(response.snapshots)
        return decodedSnapshots
    }

    func loadNextImages() {
        if isLoading { return }
        Task {
            isLoading = true
            do {
                // snapshots.count seems to stay at the same value all the time (e.g. 108). Why?
                print("loadNextImages: index = \(index), snapshots.count = \(snapshots.count)")
                var count = 0
                for timestamps in timestamps[timestampIndex..<timestamps.count] {
                    let newSnapshots = if timestamps.source == .xpc {
                        try await imageLoader.loadImagesFromXPC(timestamps: timestamps)
                    } else {
                        try await loadImagesFromDisk(timestamps: timestamps)
                    }
                    snapshots.insert(contentsOf: newSnapshots, at: snapshots.count)
                    timestampIndex += 1
                    count += newSnapshots.count
                    if count + snapshots.count >= arraySize + arrayOffset {
                        break
                    }
                }

                // TODO: use ObservableObject so that these changes are published only after updating both values
                self.snapshots.removeFirst(min(index, count))
                self.index -= min(index, count)
            } catch {
                log("Error in loadNextImages: \(error)")
            }
            isLoading = false
        }
    }

    func loadPreviousImages() {
        if isLoading { return }
        Task {
            isLoading = true
            do {
                print("loadPreviousImages: index = \(index), snapshots.count = \(snapshots.count)")
                var count = 0
                for timestamps in timestamps[0..<timestampIndex].reversed() {
                    let newSnapshots = if timestamps.source == .xpc {
                        try await imageLoader.loadImagesFromXPC(timestamps: timestamps)
                    } else {
                        try await loadImagesFromDisk(timestamps: timestamps)
                    }
                    snapshots.insert(contentsOf: newSnapshots, at: 0)
                    index += newSnapshots.count
                    timestampIndex -= 1
                    count += newSnapshots.count
                    if count + snapshots.count >= arraySize + arrayOffset {
                        break
                    }
                }

                self.snapshots.removeLast(count)
            } catch {
                log("Error in loadPreviousImages: \(error)")
            }
            isLoading = false
        }
    }

    // TODO: bug: if load{Next,Previous}Images is running when this function is called (via the search bar), it will not execute
    // Should probably put all three functions in an actor
    func loadImages(query: SearchQuery? = nil, offset: Int = 0, indexOffset: Int = 0) {
        if isLoading { return }

        lastQuery = query
        let searchText = query?.text ?? ""
        let search = Search.parse(text: searchText)

        Task {
            isLoading = true
            do {
                let xpcTimestamps = try await imageLoader.getTimestamps(from: search.minTimestamp, to: search.maxTimestamp)
                let diskTimestamps = try getTimestamps(from: search.minTimestamp, to: search.maxTimestamp)
                timestamps = (xpcTimestamps + diskTimestamps).sorted { $0.block < $1.block }

                snapshotCount = timestamps.reduce(0) { $0 + $1.count }
                timestampIndex = 0
                totalIndex = offset
                index = 0
                snapshots = []

                var count = 0
                for timestamps in timestamps {
                    timestampIndex += 1
                    count += timestamps.count
                    if count < offset {
                        continue
                    }
                    let newSnapshots = if timestamps.source == .xpc {
                        try await imageLoader.loadImagesFromXPC(timestamps: timestamps)
                    } else {
                        try await loadImagesFromDisk(timestamps: timestamps)
                    }
                    snapshots.insert(contentsOf: newSnapshots, at: snapshots.count)
                    if snapshots.count > arraySize {
                        break
                    }
                }

                index += indexOffset
                totalIndex += indexOffset

                print("loadImages: index = \(index), snapshots.count = \(snapshots.count)")
            } catch {
                print("Error loading images: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    func getTimestamps(from minTimestamp: Int, to maxTimestamp: Int) throws -> [TimestampList] {
        do {
            let db = try Database()

            return try db.getTimestamps(from: minTimestamp, to: maxTimestamp)
        } catch {
            throw error
        }
    }

    // TODO: consider avoiding refetching some images if there's an overlap
    func setIndex(_ newIndex: Int) {
        Task { loadImages(query: lastQuery, offset: max(0, newIndex - arraySize/2), indexOffset: newIndex - arraySize/2 > 0 ? arraySize/2 : 0) }
    }

    // FIXME: when inputting into the top left textfield, the number incorrectly displays as 1 briefly
    // FIXME: sometimes stops before totalIndex = snapshotCount-1
    func nextImage() {
        Task {
            if index < snapshots.count - 1 && totalIndex < snapshotCount - 1 {
                index += 1
                totalIndex += 1

                if self.index > self.snapshots.count - arrayOffset {
                    self.loadNextImages()
                }
            }
        }
    }

    func previousImage() {
        Task {
            if self.index > 0 && self.totalIndex > 0 {
                self.index -= 1
                self.totalIndex -= 1

                if self.index < arrayOffset {
                    self.loadPreviousImages()
                }
            }
        }
    }

    var atFirstImage: Bool {
        return totalIndex == 0
    }

    var atLastImage: Bool {
        return totalIndex == snapshots.count - 1
    }
}
