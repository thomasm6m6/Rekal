import Foundation
import ImageIO
import OrderedCollections

// TODO queue? (e.g. using GCD)
class SnapshotData {
    private var snapshots = SnapshotDictionary() // last 5-10 min of images

    // TODO use e.g. private(set) instead of a getter method
    func get() -> SnapshotDictionary {
        return snapshots
    }

    func get(key: Int) -> Snapshot? {
        return snapshots[key]
    }
    
    func getRange(from: Int, to: Int) -> SnapshotDictionary {
        return snapshots.filter {
            $0.key > from && $0.key < to
        }
    }

    func add(timestamp: Int, snapshot: Snapshot) {
        snapshots[timestamp] = snapshot
    }

    func remove(for timestamp: Int) {
        snapshots[timestamp] = nil
    }
}
