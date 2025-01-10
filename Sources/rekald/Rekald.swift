import Foundation
import Common

// TODO use `throw` in more places
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
            let processor = try Processor(data: data, interval: 60)

            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task {
                    do { try await recorder.record() }
                    catch { log("Error capturing snapshot: \(error)") }
                }
            }

            Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                Task {
                    do { try await processor.process() }
                    catch { log("Error processing snapshots: \(error)") }
                }
            }
        } catch {
            log("Error: \(error)")
        }

        RunLoop.current.run()
    }
}