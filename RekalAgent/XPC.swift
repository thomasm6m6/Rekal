import Foundation

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
            let snapshots = data.getRecent()
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
                    try await processor.process()
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
