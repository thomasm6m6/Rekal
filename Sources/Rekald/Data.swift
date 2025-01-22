import Foundation
import OrderedCollections
import Common

actor Data {
    private var snapshots: OrderedDictionary<Int, Snapshot> = [:] // last 5-10 min of images

    func get() -> OrderedDictionary<Int, Snapshot> {
        return snapshots
    }

    func get(key: Int) -> Snapshot? {
        return snapshots[key]
    }

    func add(timestamp: Int, snapshot: Snapshot) {
        snapshots[timestamp] = snapshot
    }

    func remove(for timestamp: Int) {
        snapshots[timestamp] = nil
    }
}