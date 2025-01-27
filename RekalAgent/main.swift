import Foundation

// TODO: use `throw` in more places
// TODO: exit in case of fatal errors like failing to create the db file
//
// TODO: graceful exit where a gentle quit request (e.g. ctrl+c, but
// also whatever macOS would give it e.g. when it wants to shut down)
// makes it process the remaining images (maybe), but a hard request
// (e.g. 2 ctrl+c's) makes it quit immediately.
// Also, need to think about what to do if there's already a file
// corresponding to the timeframe we're trying to write for (e.g. if
// the process were quit and then immediately restarted.)
//
// TODO: keep logs in Application Support directory(?)
//
// FIXME: loginitem seems a bit messed up. Doesn't show in user-configurable login items, and even after being unregistered it comes back upon restart
//
// TODO: change display name so that control center message says "Rekal recorded the screen recently" rather than "RekalAgent recorded the screen recently"
//
// TODO: figure out logging
// TODO: swift 6


func startListener() {
    do {
        _ = try XPCListener(service: "com.thomasm6m6.RekalAgent.xpc") { request in
            request.accept { message in
                return performTask(with: message)
            }
        }
    } catch {
        print("Failed to create listener, error: \(error)")
    }
}

func performTask(with message: XPCReceivedMessage) -> Encodable? {
    do {
        let request = try message.decode(as: XPCRequest.self)

        switch request.messageType {
        case .fetchImages:
//            let now = Int(Date().timeIntervalSince1970)
//            let snapshots = data.getRange(from: now - 600, to: now)
//            let snapshots = data.getRecent()
            let snapshots = data.get()
            let encodedSnapshots = encodeSnapshots(snapshots)
            return XPCResponse(reply: .snapshots(encodedSnapshots))
        case .controlCommand(.startRecording):
            print("Start recording")
        case .controlCommand(.pauseRecording):
            print("Stop recording")
        case .controlCommand(.processImages):
            let semaphore = DispatchSemaphore(value: 0)
            var result = XPCResponse(reply: .error("Unknown error processing"))

            Task {
                do {
                    try await processor.process(now: true)
                    result = XPCResponse(reply: .didProcess)
                } catch {
                    result = XPCResponse(reply: .error("Processing failed: \(error)"))
                }
                semaphore.signal()
            }
            semaphore.wait()
            return result
        case .statusQuery(.imageCount):
            return XPCResponse(reply: .imageCount(data.get().count))
        case .statusQuery(.recordingStatus):
            return XPCResponse(reply: .status(Bool.random() ? .recording: .stopped))
        }
    } catch {
        print("Failed to decode received message, error: \(error)")
    }
    return nil
}

func log2(_ message: String) {
    let fileURL = URL(fileURLWithPath: "/tmp/a.log")

    do {
        // Check if file exists; if it does, append, otherwise create a new file
        if FileManager.default.fileExists(atPath: fileURL.path) {
            // Append the message to the file
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle.seekToEndOfFile()
            if let data = "\(Date.now)\t\(message)\n".data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            // Create a new file and write the message
            try "\(Date.now)\t\(message)\n".write(to: fileURL, atomically: true, encoding: .utf8)
        }
    } catch {
        print("Error writing to file: \(error)")
    }
}

log2("Starting daemon...")

let data = SnapshotData()
let recorder = Recorder(data: data, interval: 1.0)

let processor: Processor
do { try processor = Processor(data: data, interval: 300) } catch {
    log2("Error initializing Processor")
    exit(1)
}

Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    Task {
        do { try await recorder.record() } catch {
            log2("Error capturing snapshot: \(error)")
        }
    }
}

Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
    Task {
        do { try await processor.process() } catch {
            log2("Error processing snapshots: \(error)")
        }
    }
}

startListener()
//dispatchMain()

RunLoop.current.run()
