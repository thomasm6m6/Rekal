import Foundation
import Common

// TODO replayd is using 4.5gb of memory rn. that might be a problem.
// TODO use `throw` in more places
// FIXME figure out why I ended up with a 1 frame mp4 one time
//       (relatedly, `subrecords` one time only had a length of 1)
// TODO exit in case of fatal errors like failing to create the db file

// TODO graceful exit where a gentle quit request (e.g. ctrl+c, but
// also whatever macOS would give it e.g. when it wants to shut down)
// makes it process the remaining images (maybe), but a hard request
// (e.g. 2 ctrl+c's) makes it quit immediately.
// Also, need to think about what to do if there's already a file
// corresponding to the timeframe we're trying to write for (e.g. if
// the process were quit and then immediately restarted.)

@main
struct Rekald {
    static func main() {
        log("Starting daemon...")

        do {
            let data = Data()

            let recorder = Recorder(data: data, interval: 1.0)
            let processor = try Processor(data: data, interval: 300)

            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task {
                    do { try await recorder.record() }
                    catch { print("Error capturing snapshot: \(error)") }
                }
            }

            Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
                Task {
                    log("running process function")
                    do { try await processor.process() }
                    catch { print("Error processing snapshots: \(error)") }
                }
            }
        } catch {
            log("Error: \(error)")
        }

        RunLoop.current.run()
    }
}