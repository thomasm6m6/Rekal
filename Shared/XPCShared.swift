import Foundation
import CoreGraphics

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
    case getSnapshots(timestamps: [Int])
    case getTimestamps(query: Query)
    case getImageCount
    case setRecording(Bool)
}

enum Reply: Codable {
    case snapshots([EncodedSnapshot])
    case timestamps([Int])
    case recordingStatus(Bool)
    case imageCount(Int)
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
