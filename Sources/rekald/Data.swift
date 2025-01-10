import Foundation
import Common

actor Data {
    private var snapshots: [Int: Snapshot] = [:] // last 5-10 min of images

    func get() -> [Int: Snapshot] {
        return snapshots
    }

    func get(key: Int) -> Snapshot? {
        return snapshots[key]
    }

    func add(timestamp: Int, snapshot: Snapshot) {
        snapshots[timestamp] = snapshot
    }

    func remove(for timestamp: Int) {
        snapshots.removeValue(forKey: timestamp)
    }
}