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

//    func getRange(from: Int, to: Int) -> [Snapshot] {
//        return snapshots.filter {
//            $0.key > from && $0.key < to
//        }
//    }
//
//    func getRecent() -> [Snapshot] {
//        // TODO: test whether this is fast at 600
//        let keys = snapshots.keys.suffix(600)
//        return keys.reduce(into: [:]) { $0[$1] = snapshots[$1] }
//    }

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
