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

//    func get(with timestamps: [TimestampObject]) -> [Snapshot] {
//        var result: [Snapshot] = []
//        for snapshot in snapshots {
//            if let _ = timestamps.first(where: { $0.timestamp == snapshot.timestamp }) {
//                result.append(snapshot)
//            }
//        }
//        return result
//    }

//    func getTimestamps(minTimestamp: Int, maxTimestamp: Int) -> [TimestampObject] {
//        var timestamps: [TimestampObject] = []
//        for snapshot in snapshots {
//            if snapshot.timestamp >= minTimestamp && snapshot.timestamp <= maxTimestamp {
//                timestamps.append(TimestampObject(
//                    timestamp: snapshot.timestamp,
//                    source: .xpc,
//                    videoTimestamp: 0
//                ))
//            }
//        }
//        return timestamps
//    }

    func getTimestampBlocks(minTimestamp: Int, maxTimestamp: Int) -> [TimestampList] {
        var timestamps: [TimestampList] = []
        for snapshot in snapshots {
            let block = snapshot.timestamp / 300 * 300
            if timestamps.count > 0, timestamps[timestamps.count-1].block == block {
                timestamps[timestamps.count-1].timestamps.append(snapshot.timestamp)
            } else {
                timestamps.append(TimestampList(
                    block: block,
                    timestamps: [snapshot.timestamp],
                    source: .xpc
                ))
            }
        }
        return timestamps
    }

    func get(from minTimestamp: Int, to maxTimestamp: Int) -> [Snapshot] {
//        let first = snapshots.firstIndex { $0.timestamp > from }
//        let last = snapshots.firstIndex { $0.timestamp < to }
//        return snapshots[first..<last]
        return snapshots.filter {
            $0.timestamp > minTimestamp && $0.timestamp < maxTimestamp
        }
    }
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
