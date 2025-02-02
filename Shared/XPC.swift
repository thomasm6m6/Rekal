import Foundation
import CoreGraphics
import ImageIO
import ServiceManagement

struct DecodeRequest: Codable {
    let url: URL
    let timestamp: Int
    let action: Action?
}

enum Action: Codable {
    case quit
}

struct DecodeResponse: Codable {
    let snapshots: [EncodedSnapshot]
}

enum XPCDecodingError: Error {
    case error(String)
}

struct XPCRequest: Codable {
    let messageType: MessageType
}

struct XPCResponse: Codable {
    let reply: Reply
}

enum MessageType: Codable {
//    case fetchImages(timestamps: [TimestampObject])
    case fetchImagesFromRange(minTimestamp: Int, maxTimestamp: Int)
//    case getTimestamps(min: Int, max: Int)
    case getTimestampBlocks(min: Int, max: Int)
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
    case snapshots([EncodedSnapshot])
//    case timestamps([TimestampObject])
    case timestampBlocks([TimestampList])
    case status(Status)
    case imageCount(Int)
    case didProcess
    case error(String)
}

enum Status: Codable {
    case recording
    case stopped
}

func encodeSnapshots(_ snapshots: [Snapshot]) -> [EncodedSnapshot] {
    var encodedSnapshots: [EncodedSnapshot] = []
    for snapshot in snapshots {
        var data: Data?
        if let image = snapshot.image {
            data = image.png
        }
        encodedSnapshots.append(EncodedSnapshot(
            data: data,
            timestamp: snapshot.timestamp,
            info: snapshot.info,
            pHash: snapshot.pHash,
            ocrData: snapshot.ocrData
        ))
    }
    return encodedSnapshots
}

func decodeSnapshots(_ encodedSnapshots: [EncodedSnapshot]) -> [Snapshot] {
    var snapshots: [Snapshot] = []
    for snapshot in encodedSnapshots {
        var cgImage: CGImage?

        if let data = snapshot.data, let provider = CGDataProvider(data: data as NSData) {
            cgImage = CGImage(
                pngDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }

        snapshots.append(Snapshot(
            image: cgImage,
            timestamp: snapshot.timestamp,
            info: snapshot.info,
            pHash: snapshot.pHash,
            ocrData: snapshot.ocrData
        ))
    }
    return snapshots
}

func buildListFromResponse(dictionary: XPCDictionary) -> [Snapshot]? {
    return nil
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
