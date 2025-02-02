import Foundation
import CoreGraphics

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

struct SnapshotInfo: Codable, Sendable {
    let windowId: Int
    let rect: CGRect
    var windowName: String?
    var appId: String?
    var appName: String?
    var url: String?

    init(
        windowId: Int, rect: CGRect, windowName: String? = nil, appId: String? = nil,
        appName: String? = nil, url: String? = nil
    ) {
        self.windowId = windowId
        self.rect = rect
        self.windowName = windowName
        self.appId = appId
        self.appName = appName
        self.url = url
    }
}

struct Snapshot: Sendable {
    var image: CGImage?
    let timestamp: Int
    let info: SnapshotInfo
    let pHash: String
    var ocrData: String?

    init(image: CGImage?, timestamp: Int, info: SnapshotInfo, pHash: String, ocrData: String? = nil) {
        self.image = image
        self.timestamp = timestamp
        self.info = info
        self.pHash = pHash
        self.ocrData = ocrData
    }
}

struct EncodedSnapshot: Codable {
    var data: Data?
    let timestamp: Int
    let info: SnapshotInfo
    let pHash: String
    let ocrData: String?

    init(data: Data?, timestamp: Int, info: SnapshotInfo, pHash: String, ocrData: String? = nil) {
        self.data = data
        self.timestamp = timestamp
        self.info = info
        self.pHash = pHash
        self.ocrData = ocrData
    }
}

struct Video: Sendable {
    let timestamp: Int
    let url: URL

    init(timestamp: Int, url: URL) {
        self.timestamp = timestamp
        self.url = url
    }
}

struct TimestampList: Codable {
    let block: Int
    var timestamps: [Int]
    let source: SnapshotSource

    var count: Int {
        return timestamps.count
    }
}

// Can/should this be put inside TimestampObject?
enum SnapshotSource: Codable {
//    case disk(videoTimestamp: Int)
    case disk
    case xpc
}

func log(_ string: String) {
    print("\(Date())\t\(string)")
}
