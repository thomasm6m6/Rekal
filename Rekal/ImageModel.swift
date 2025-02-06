import Foundation

// TODO: load timestamps first so we can display the counter instantly
// TODO: get snapshots via XPC in chunks
@MainActor
class ImageModel: ObservableObject {
    @Published var snapshots: [Snapshot] = [] // loaded snapshots
//    @Published var timestamps: [Int] = [] // all timestamps matching current search
    @Published var index = 0 // index within `snapshots`
//    @Published var timestampIndex = 0 // index within `timestamps`
    @Published var snapshotCount = 0 // total number of snapshots
    @Published var totalIndex = 0 // index from [0, snapshotCount)

    private let xpcManager = XPCManager()

    // FIXME: this shouldn't be here
    func setRecording(_ status: Bool) async throws -> Bool {
        return try await xpcManager.setRecording(status)
    }

    // TODO: bug: if load{Next,Previous}Images is running when this function is called (via the search bar), it will not execute
    // Should probably put all three functions in an actor
    func loadImages(query: Query) {
        Task {
            do {
                index = 0
                snapshots = []

                let xpcTimestamps = try await getTimestampsFromXPC(query: query)
                snapshotCount = xpcTimestamps.count
                let xpcSnapshots = try await getSnapshotsFromXPC(timestamps: xpcTimestamps)
                snapshots.insert(contentsOf: xpcSnapshots, at: snapshots.count)

                let diskTimestamps = try await getTimestampsFromDisk(query: query)
                snapshotCount += diskTimestamps.count
                let diskSnapshots = try await getSnapshotsFromDisk(timestamps: diskTimestamps)
                snapshots.insert(contentsOf: diskSnapshots, at: snapshots.count)

                let apiTimestamps = try await getTimestampsFromAPI(query: query)
                snapshotCount += apiTimestamps.count
                let apiSnapshots = try await getSnapshotsFromAPI(timestamps: apiTimestamps)
                snapshots.insert(contentsOf: apiSnapshots, at: snapshots.count)
            } catch {
                print("Error loading images: \(error.localizedDescription)")
            }
        }
    }

    func getTimestampsFromXPC(query: Query) async throws -> [Int] {
        return try await xpcManager.getTimestamps(query: query)
    }

    func getTimestampsFromDisk(query: Query) async throws -> [Int] {
        return []
    }

    func getTimestampsFromAPI(query: Query) async throws -> [Int] {
        return []
    }

    func getSnapshotsFromXPC(timestamps: [Int]) async throws -> [Snapshot] {
        return try await xpcManager.getSnapshots(timestamps: timestamps)
    }

    func getSnapshotsFromDisk(timestamps: [Int]) async throws -> [Snapshot] {
        return []
    }

    func getSnapshotsFromAPI(timestamps: [Int]) async throws -> [Snapshot] {
        return []
    }

    func nextImage() {
        Task {
            if index < snapshots.count - 1 && !atLastImage {
                index += 1
                totalIndex += 1
            }
        }
    }

    func previousImage() {
        Task {
            if index > 0 && !atFirstImage {
                index -= 1
                totalIndex -= 1
            }
        }
    }

    var atFirstImage: Bool {
        return totalIndex <= 0
    }

    var atLastImage: Bool {
        return totalIndex >= snapshotCount - 1
    }
}
