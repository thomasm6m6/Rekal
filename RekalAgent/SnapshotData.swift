import Foundation
import ImageIO

enum SnapshotDataError: Error {
    case error(String)
}

// TODO: queue? (e.g. using GCD)
class SnapshotData {
    private var snapshots: [Snapshot] = []

    // TODO: use e.g. private(set) instead of a getter method
    func get() -> [Snapshot] {
        return snapshots
    }

    func get(at timestamp: Int) -> Snapshot? {
        return snapshots.first { $0.timestamp == timestamp }
    }

    func getTimestamps(query: Query) -> [Int] {
        return snapshots
            .filter { $0.timestamp >= query.minTimestamp && $0.timestamp <= query.maxTimestamp }
            .map { $0.timestamp }
    }

    func get(timestamps: [Int]) -> [Snapshot] {
        return snapshots.filter { timestamps.contains($0.timestamp) }
    }

    func add(timestamp: Int, snapshot: Snapshot) {
        snapshots.append(snapshot)
    }

    func remove(at timestamp: Int) throws {
        guard let index = snapshots.firstIndex(where: { $0.timestamp == timestamp }) else {
            throw SnapshotDataError.error("Timestamp '\(timestamp)' not found in array")
        }
        snapshots.remove(at: index)
    }
}
