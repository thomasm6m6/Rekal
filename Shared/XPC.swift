import Foundation
import CoreGraphics
import ImageIO

class XPCManager {
    var session: XPCSession?

    func setup() {
        if session == nil {
            session = try? XPCSession(machService: "com.thomasm6m6.RekalAgent.xpc")
        }
    }
}

struct XPCRequest: Codable {
    let messageType: MessageType
}

struct XPCResponse: Codable {
    let reply: Reply
}

enum MessageType: Codable {
    case fetchImages
    case controlCommand(Command)
    case statusQuery(Query)
}

enum Command: Codable {
    case startRecording
    case pauseRecording
    case processImages
}

enum Query: Codable {
    case imageCount
    case recordingStatus
}

enum Reply: Codable {
    case snapshots(EncodedSnapshotList)
    case status(Status)
    case imageCount(Int)
    case didProcess
    case error(String)
}

enum Status: Codable {
    case recording
    case stopped
}

func encodeSnapshots(_ snapshots: SnapshotList) -> EncodedSnapshotList {
    var encodedSnapshots: EncodedSnapshotList = [:]
    for (key, value) in snapshots {
        var data: Data?
        if let image = value.image {
            data = image.png
        }
        encodedSnapshots[key] = EncodedSnapshot(
            data: data,
            timestamp: value.timestamp,
            info: value.info,
            pHash: value.pHash,
            ocrData: value.ocrData
        )
    }
    return encodedSnapshots
}

func decodeSnapshots(_ encodedSnapshots: EncodedSnapshotList) -> SnapshotList {
    var snapshots: SnapshotList = [:]
    for (key, value) in encodedSnapshots {
        var cgImage: CGImage?

        if let data = value.data, let provider = CGDataProvider(data: data as NSData) {
            cgImage = CGImage(
                pngDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }

        snapshots[key] = Snapshot(
            image: cgImage,
            timestamp: value.timestamp,
            info: value.info,
            pHash: value.pHash,
            ocrData: value.ocrData
        )
    }
    return snapshots
}

extension CGImage {
    var png: Data? {
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
