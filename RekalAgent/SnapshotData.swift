import Foundation
import ImageIO
import OrderedCollections

// TODO queue? (e.g. using GCD)
class SnapshotData {
    private var snapshots = SnapshotList() // last 5-10 min of images

    // TODO use e.g. private(set) instead of a getter method
    func get() -> SnapshotList {
        return snapshots
    }

    func get(key: Int) -> Snapshot? {
        return snapshots[key]
    }

    func getRange(from: Int, to: Int) -> SnapshotList {
        return snapshots.filter {
            $0.key > from && $0.key < to
        }
    }

    func getRecent() -> SnapshotList {
        // TODO test whether this is fast at 600
        let keys = snapshots.keys.suffix(600)
        return keys.reduce(into: [:]) { $0[$1] = snapshots[$1] }
    }

    func add(timestamp: Int, snapshot: Snapshot) {
        snapshots[timestamp] = snapshot
    }

    func remove(for timestamp: Int) {
        snapshots[timestamp] = nil
    }
}
