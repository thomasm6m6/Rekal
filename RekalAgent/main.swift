import Foundation

// TODO use `throw` in more places
// TODO exit in case of fatal errors like failing to create the db file
//
// TODO graceful exit where a gentle quit request (e.g. ctrl+c, but
// also whatever macOS would give it e.g. when it wants to shut down)
// makes it process the remaining images (maybe), but a hard request
// (e.g. 2 ctrl+c's) makes it quit immediately.
// Also, need to think about what to do if there's already a file
// corresponding to the timeframe we're trying to write for (e.g. if
// the process were quit and then immediately restarted.)
//
// TODO keep logs in Application Support directory(?)
//
// FIXME loginitem seems a bit messed up. Doesn't show in user-configurable login items, and even after being unregistered it comes back upon restart
//
// TODO change display name so that control center message says "Rekal recorded the screen recently" rather than "RekalAgent recorded the screen recently"
//
// TODO figure out logging

log("Starting daemon...")

let data = SnapshotData()
let recorder = Recorder(data: data, interval: 1.0)

let processor: Processor
do { try processor = Processor(data: data, interval: 300) } catch {
    log("Error initializing Processor")
    exit(1)
}

Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    Task {
        do { try await recorder.record() } catch {
            log("Error capturing snapshot: \(error)")
        }
    }
}

Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
    Task {
        do { try await processor.process() } catch {
            log("Error processing snapshots: \(error)")
        }
    }
}

startListener()
//dispatchMain()

RunLoop.current.run()
