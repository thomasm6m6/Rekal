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
            print("Fetch images")
        case .controlCommand(.startRecording):
            print("Start recording")
        case .controlCommand(.pauseRecording):
            print("Stop recording")
        case .controlCommand(.processImages):
            print("Process images")
        case .statusQuery(.imageCount):
            return XPCResponse(reply: .imageCount(Int.random(in: 1..<100)))
        case .statusQuery(.recordingStatus):
            return XPCResponse(reply: .status(Bool.random() ? .recording: .stopped))
        }
    } catch {
        print("Failed to decode received message, error: \(error)")
    }
    return nil
}
