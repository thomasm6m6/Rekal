import Foundation
import Common

actor Data {
    // Might make more sense to just define this in Recorder and pass Recorder instance to Processor
    private var records: [Record] = [] // last 5-10 min of images

    func get() -> [Record] {
        return records
    }

    func get(at index: Int) -> Record {
        return records[index]
    }

    func add(record: Record) {
        records.append(record)
    }

    func remove(at index: Int) {
        records.remove(at: index)
    }
}