import SwiftUI
import Vision
import AVFoundation

// TODO: make "open rekal" function properly
// TODO: alternative to passing frameManager manually to every custom view?
// TODO: use `public`/`private`/`@Published` correctly
// FIXME: "onChange(of: CGImageRef) action tried to update multiple times per frame"
// TODO: easily noticeable warning (maybe a popup, and/or an exclamation point through the menu bar icon) if the record function throws when it shouldn't
// FIXME: applescript
// FIXME: "Publishing changes from within view updates is not allowed, this will cause undefined behavior" (nextImage/previousImage)
// TODO: combine frameManager, xpcManager, etc into a ContextManager?
// TODO: search bar doesn't show in overflow menu when window width is small

struct SearchOptions {
    var fullText: Bool
}

struct Search {
    var minTimestamp: Int
    var maxTimestamp: Int
    var terms: [String]

    static func parse(text: String) -> Search {
        let today = Int(Calendar.current.startOfDay(for: Date.now).timeIntervalSince1970)
        return Search(
            minTimestamp: today,
            maxTimestamp: today + 24 * 60 * 60,
            terms: []
        )
    }
}

enum ImageError: Error {
    case xpcError(String)
    case decodingError(String)
}

class ImageModel: ObservableObject {
    @Published var snapshots = SnapshotList()
    @Published var index = 0

    // TODO: warning: "Publishing changes from within view updates is not allowed, this will cause undefined behavior"
    func nextImage() {
        if !atLastImage {
            index += 1
        }
    }

    func previousImage() {
        if !atFirstImage {
            index -= 1
        }
    }

    var atFirstImage: Bool {
        return index == 0
    }

    var atLastImage: Bool {
        return index == snapshots.count - 1
    }
}

struct ContentView: View {
    @FocusState private var isFocused: Bool

    @StateObject private var imageModel = ImageModel()

//    @State private var snapshots = SnapshotList()
//    @State private var index = 0

    private let backgroundColor = Color(red: 18/256, green: 18/256, blue: 18/256) // #121212

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            NavigationStack {
                VStack {
                    Spacer()

                    if !imageModel.snapshots.isEmpty {
                        let timestamp = imageModel.snapshots.keys[imageModel.index]
                        if let snapshot = imageModel.snapshots[timestamp],
                           let image = snapshot.image {
                            Group {
                                Image(image, scale: 1.0, label: Text("Screenshot"))
                                    .resizable()
                                    .scaledToFit()
                            }
                            .padding()
                        } else {
                            Text("Failed to get the image")
                        }
                    } else {
                        Text("No images to display")
                    }

                    Spacer()
                }
                .onAppear {
                    loadImages()
                }
            }
            .toolbar {
                Toolbar(imageModel: imageModel)
            }
            .toolbarBackground(backgroundColor)
        }
        .onAppear {
            _ = LaunchManager.registerLoginItem()
            _ = LaunchManager.registerLaunchAgent()
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            isFocused = true
        }
        .onKeyPress(.leftArrow) {
            imageModel.previousImage()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            imageModel.nextImage()
            return .handled
        }
    }

    func loadImages(search searchText: String = "") {
        loadImagesFromXPC()

        let search = Search.parse(text: searchText)
        loadImagesFromDisk(search: search)
    }

    // FIXME: returns images out of order
    private func loadImagesFromXPC() {
        Task.detached {
            do {
                let xpcSession = try XPCSession(machService: "com.thomasm6m6.RekalAgent.xpc")
                defer { xpcSession.cancel(reason: "Done") }

                let request = XPCRequest(messageType: .fetchImages)

                let response = try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<XPCResponse, any Error>) in
                    do {
                        try xpcSession.send(request) { result in
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
                    let decodedSnapshots = decodeSnapshots(encodedSnapshots)
                    for (timestamp, snapshot) in decodedSnapshots {
                        await MainActor.run {
                            if self.imageModel.snapshots[timestamp] == nil {
                                self.imageModel.snapshots[timestamp] = snapshot
                            }
                        }
                    }
                default:
                    log("Unexpected response")
                }
            } catch {
                log("Error: \(error)")
            }
        }
    }

    private func loadImagesFromDisk(search: Search) {
        Task {
            do {
                let db = try Database()

                let videos = try db.videosBetween(minTime: search.minTimestamp,
                                                  maxTime: search.maxTimestamp)

                await withTaskGroup(of: SnapshotList?.self) { group in
                    for (_, video) in videos {
                        do {
                            let snapshotsInVideo = try db.snapshotsInVideo(videoTimestamp: video.timestamp)

                            group.addTask {
                                return try? await self.decodeVideo(video: video, snapshotsInVideo: snapshotsInVideo)
                            }
                        } catch {
                            log("Error querying database: \(error)")
                        }
                    }

                    for await snapshotList in group {
                        if let snapshotList = snapshotList {
                            // TODO: Might be able to use a merge function
                            for (timestamp, snapshot) in snapshotList {
                                imageModel.snapshots[timestamp] = snapshot
                            }
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

}
