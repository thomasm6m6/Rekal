import Foundation
import OrderedCollections

// TODO queue? (e.g. using GCD)
class SnapshotData {
    private var snapshots: OrderedDictionary<Int, Snapshot> = [:] // last 5-10 min of images
    var snapshotCount: Int = 0

    func get() -> OrderedDictionary<Int, Snapshot> {
        return snapshots
    }

    func get(key: Int) -> Snapshot? {
        return snapshots[key]
    }

    func add(timestamp: Int, snapshot: Snapshot) {
        snapshots[timestamp] = snapshot
        snapshotCount = snapshots.count
    }

    func remove(for timestamp: Int) {
        snapshots[timestamp] = nil
        snapshotCount = snapshots.count
    }
}
