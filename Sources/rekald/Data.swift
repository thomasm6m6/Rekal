import Foundation
import Common

actor Data {
    private var snapshots: [Snapshot] = [] // last 5-10 min of images

    func get() -> [Snapshot] {
        return snapshots
    }

    func get(at index: Int) -> Snapshot {
        return snapshots[index]
    }

    func add(snapshot: Snapshot) {
        snapshots.append(snapshot)
    }

    func remove(at index: Int) {
        snapshots.remove(at: index)
    }
}