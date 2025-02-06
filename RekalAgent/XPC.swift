import Foundation
import Dispatch

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
        case .getTimestamps(query: let query):
            return XPCResponse(reply: .timestamps(data.getTimestamps(query: query)))
        case .getSnapshots(timestamps: let timestamps):
            let snapshots = data.get(timestamps: timestamps)
            let encodedSnapshots = encodeSnapshots(snapshots)
            return XPCResponse(reply: .snapshots(encodedSnapshots))
        case .setRecording(let status):
            let semaphore = DispatchSemaphore(value: 0)
            var isRecording = false
            Task {
                await recorder.setRecording(status)
                isRecording = await recorder.isRecording
                semaphore.signal()
            }
            semaphore.wait()
            return XPCResponse(reply: .recordingStatus(isRecording))
        case .getImageCount:
            return XPCResponse(reply: .imageCount(data.get().count))
        }
    } catch {
        print("Failed to decode received message, error: \(error)")
    }
    return nil
}
